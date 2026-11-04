# Approved models

Every `.rbxm` file here becomes a child of `ServerStorage.Assets` in the
published game (see `deploy.project.json`), named after the file:
`Krampus.rbxm` -> `ServerStorage.Assets.Krampus`. The required parts for each
name are listed in the top-level README.

Only models Josh approved through the models gallery go here.

To add one: in Studio, right-click the model in `ServerStorage.Assets` >
Save to File... > `.rbxm`, name it exactly as the game expects, and commit it.
CI deploys replace the whole place, so a model that is only in Studio is
wiped on the next deploy.

Import Meshy meshes with a colour texture only (MeshPart TextureID), not PBR,
and no unions: Open Cloud can't publish `SurfaceAppearance` or unions, and the
deploy stops if it finds one (`tools/deploy.luau` lists them).
