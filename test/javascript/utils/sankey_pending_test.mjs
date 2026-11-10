import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  layoutPendingFlows,
  PENDING_SLOT,
  linkPath,
  pendingReserve,
} from "../../../app/javascript/utils/sankey_pending.mjs";

// Income at x 16, Cash Flow at 300, spending at 584, 1 px per unit.
const nodes = [
  { id: "income_salary", kind: "income", value: 200, x0: 16, x1: 31, y0: 16, y1: 216 },
  { id: "cash_flow_node", kind: "cash_flow", value: 200, x0: 300, x1: 315, y0: 16, y1: 216 },
  { id: "expense_rent", kind: "expense", value: 120, x0: 584, x1: 599, y0: 16, y1: 136 },
  { id: "expense_food", kind: "expense", value: 80, x0: 584, x1: 599, y0: 162, y1: 242 },
];
const owed = (id, value) => ({ id, direction: "owed_to_me", name: id, value });
const owe = (id, value) => ({ id, direction: "i_owe", name: id, value });

describe("pendingReserve", () => {
  it("is zero with nothing open", () => {
    assert.equal(pendingReserve([]), 0);
    assert.equal(pendingReserve(undefined), 0);
  });

  it("makes room for the longer side", () => {
    const one = pendingReserve([owed("a", 1)]);
    assert.equal(pendingReserve([owed("a", 1), owed("b", 1), owe("c", 1)]) - one, PENDING_SLOT);
  });
});

describe("layoutPendingFlows", () => {
  it("draws nothing with nothing open", () => {
    assert.deepEqual(layoutPendingFlows(nodes, [], { nodeWidth: 15 }), []);
  });

  it("puts money owed to you beside income and money you owe beside spending", () => {
    const [incoming, outgoing] = layoutPendingFlows(nodes, [owed("ravi", 50), owe("maya", 10)], { nodeWidth: 15 });
    assert.equal(incoming.x0, 16);
    assert.equal(outgoing.x0, 584);
    assert.equal(incoming.labelOnRight, true);
    assert.equal(outgoing.labelOnRight, false);
    // Below each column's lowest node.
    assert.ok(incoming.y0 > 216);
    assert.ok(outgoing.y0 > 242);
  });

  it("leaves the graph's nodes untouched", () => {
    const before = JSON.stringify(nodes);
    layoutPendingFlows(nodes, [owed("ravi", 5000)], { nodeWidth: 15 });
    assert.equal(JSON.stringify(nodes), before);
  });

  it("stacks rows and keeps bars between the clamps", () => {
    const flows = layoutPendingFlows(nodes, [owed("big", 100000), owed("tiny", 0.01)], { nodeWidth: 15 });
    const [big, tiny] = flows;
    assert.ok(big.y1 - big.y0 <= 24);
    assert.ok(tiny.y1 - tiny.y0 >= 6);
    assert.equal((tiny.y0 + tiny.y1) / 2 - (big.y0 + big.y1) / 2, PENDING_SLOT);
  });

  it("stops each pipe short of Cash Flow", () => {
    const [incoming, outgoing] = layoutPendingFlows(nodes, [owed("ravi", 50), owe("maya", 10)], { nodeWidth: 15 });
    const start = (path) => Number(path.slice(1).split(",")[0]);
    const end = (path) => Number(path.split("C")[1].split(",").at(-2));
    assert.equal(start(incoming.pipe), 31);
    assert.ok(end(incoming.pipe) < 300);
    assert.equal(end(outgoing.pipe), 584);
    assert.ok(start(outgoing.pipe) > 315);
  });

  it("works with the account view's account column as the hub", () => {
    const accounts = nodes.map((node) =>
      node.kind === "cash_flow" ? { ...node, id: "account_1", kind: "account" } : node,
    );
    const [incoming] = layoutPendingFlows(accounts, [owed("ravi", 50)], { nodeWidth: 15 });
    assert.equal(incoming.x0, 16);
    assert.ok(incoming.pipe);
  });
});

describe("linkPath", () => {
  it("draws d3's horizontal link curve", () => {
    assert.equal(linkPath({ x: 0, y: 0 }, { x: 100, y: 50 }), "M0,0C50,0,50,50,100,50");
  });
});
