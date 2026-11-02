//! luau-cov: adds coverage probes to one Luau file so the Lune test runner
//! can measure line and function coverage.
//!
//! Usage: `luau-cov <file.luau>`. Prints JSON to stdout:
//! `{ "source": "...", "lines": [..], "functions": [{ "name", "line" }] }`.
//!
//! Probes are inserted on the same line as the code they count, so line
//! numbers in errors and stack traces are unchanged:
//! - `__cl(<line>);` before every executable statement
//! - `__cf(<index>);` before the first statement of every function body
//!
//! The runner defines `__cl` and `__cf` in each module's environment.

use full_moon::ast::{Block, FunctionBody, LocalFunction, Stmt};
use full_moon::node::Node;
use full_moon::visitors::Visitor;
use std::collections::BTreeSet;

#[derive(Default)]
struct Probes {
    inserts: Vec<(usize, String)>,
    lines: BTreeSet<usize>,
    functions: Vec<(String, usize)>,
    pending_name: Option<(usize, String)>,
}

impl Probes {
    fn line_probe(&mut self, node: &impl Node) {
        if let Some(pos) = node.start_position() {
            self.lines.insert(pos.line());
            self.inserts
                .push((pos.bytes(), format!("__cl({});", pos.line())));
        }
    }
}

fn is_executable(stmt: &Stmt) -> bool {
    !matches!(
        stmt,
        Stmt::TypeDeclaration(_)
            | Stmt::ExportedTypeDeclaration(_)
            | Stmt::TypeFunction(_)
            | Stmt::ExportedTypeFunction(_)
    )
}

impl Visitor for Probes {
    fn visit_block(&mut self, block: &Block) {
        for stmt in block.stmts() {
            if is_executable(stmt) {
                self.line_probe(stmt);
            }
        }
        if let Some(last) = block.last_stmt() {
            self.line_probe(last);
        }
    }

    fn visit_function_declaration(&mut self, node: &full_moon::ast::FunctionDeclaration) {
        if let Some(pos) = node.body().start_position() {
            let name = node.name().to_string().trim().to_string();
            self.pending_name = Some((pos.bytes(), name));
        }
    }

    fn visit_local_function(&mut self, node: &LocalFunction) {
        if let Some(pos) = node.body().start_position() {
            let name = node.name().to_string().trim().to_string();
            self.pending_name = Some((pos.bytes(), name));
        }
    }

    fn visit_function_body(&mut self, body: &FunctionBody) {
        let Some(start) = body.start_position() else {
            return;
        };
        let name = match self.pending_name.take() {
            Some((bytes, name)) if bytes == start.bytes() => name,
            _ => "(anonymous)".to_string(),
        };
        // Probe goes where the body starts: before its first statement, or
        // before `end` when it is empty. (Positions after a return type are
        // unreliable for table types, so don't insert after the signature.)
        let block = body.block();
        let after = match block.stmts().next() {
            Some(stmt) => stmt.start_position(),
            None => match block.last_stmt() {
                Some(last) => last.start_position(),
                None => body.end_token().start_position(),
            },
        };
        if let Some(after) = after {
            let index = self.functions.len();
            self.functions
                .push((format!("{name}:{}", start.line()), start.line()));
            self.inserts
                .push((after.bytes(), format!("__cf({index});")));
        }
    }
}

fn main() {
    let path = std::env::args()
        .nth(1)
        .expect("usage: luau-cov <file.luau>");
    let source = std::fs::read_to_string(&path).expect("can't read file");
    let ast = match full_moon::parse(&source) {
        Ok(ast) => ast,
        Err(errors) => {
            for e in errors {
                eprintln!("{path}: {e}");
            }
            std::process::exit(1);
        }
    };

    let mut probes = Probes::default();
    probes.visit_ast(&ast);

    // Insert from the end so earlier byte offsets stay valid.
    probes.inserts.sort_by_key(|(at, _)| std::cmp::Reverse(*at));
    let mut out = source.clone();
    for (at, text) in &probes.inserts {
        out.insert_str(*at, text);
    }

    let functions: Vec<_> = probes
        .functions
        .iter()
        .map(|(name, line)| serde_json::json!({ "name": name, "line": line }))
        .collect();
    let json = serde_json::json!({
        "source": out,
        "lines": probes.lines.iter().collect::<Vec<_>>(),
        "functions": functions,
    });
    println!("{json}");
}
