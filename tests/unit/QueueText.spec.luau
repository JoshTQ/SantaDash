local Config = load("ReplicatedStorage.Shared.Config")
local QueueText = load("ReplicatedStorage.Shared.QueueText")

local MAX = Config.Lobby.CrewMax

describe("QueueText.line", function()
	it("counts up how long a Public rider has been in the queue", function()
		local q = { state = "Searching", kind = "Public", since = 100, count = 1 }
		expect(QueueText.line(q, 100)).toBe("In the queue! Finding your crew  ·  0:00")
		expect(QueueText.line(q, 107.9)).toBe("In the queue! Finding your crew  ·  0:07")
		expect(QueueText.line(q, 172)).toBe("In the queue! Finding your crew  ·  1:12")
	end)

	it("says a Party is being topped up with randoms", function()
		local q = { state = "Searching", kind = "Party", since = 10, count = 3 }
		expect(QueueText.line(q, 15)).toBe("In the queue! Topping up your party of 3  ·  0:05")
	end)

	it("shows who's aboard while friends climb in", function()
		expect(QueueText.line({ state = "Gathering", kind = "Party", count = 2 }, 0)).toBe(
			"In the queue! Waiting for your friends  ·  2/" .. MAX .. " aboard"
		)
		expect(QueueText.line({ state = "Gathering", kind = "Private", count = 1 }, 0)).toBe(
			"Private sleigh  ·  1 aboard  ·  waiting for friends"
		)
	end)

	it("announces a found crew, and a busy server", function()
		expect(QueueText.line({ state = "Found", count = 4 }, 0)).toBe(
			"Crew found! Off to the street...  ·  4/" .. MAX .. " Santas"
		)
		expect(QueueText.line({ state = "Found", count = 4, waiting = true }, 0)).toBe(
			"Crew found! Waiting for a free street... (4 Santas)"
		)
	end)

	it("keeps the requeue countdown after a run", function()
		local q = { departAt = 20, count = 2, requeue = true }
		expect(QueueText.line(q, 15.5)).toBe(
			"Heist again together! Sleigh leaves in 5  ·  2/" .. MAX .. " Santas"
		)
		q.waiting = true
		expect(QueueText.line(q, 15.5)).toBe("Heist again together! Waiting for a free street... (2 Santas)")
	end)

	it("never shows a negative wait or countdown", function()
		expect(QueueText.line({ state = "Searching", since = 50 }, 40)).toBe(
			"In the queue! Finding your crew  ·  0:00"
		)
		expect(QueueText.line({ departAt = 5, count = 1 }, 9)).toBe(
			"Sleigh leaves in 0  ·  1/" .. MAX .. " Santas"
		)
	end)
end)
