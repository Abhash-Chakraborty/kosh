import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  busiestColumn,
  columnCount,
  fitText,
  fittedHeight,
  fittedPadding,
  fittedWidth,
  labelRoom,
  MIN_COLUMN_PITCH,
  rescuedLabelShifts,
  TARGET_PADDING,
} from "../../../app/javascript/utils/sankey_fit.mjs";

const column = (x, count) => Array.from({ length: count }, () => ({ x0: x, x1: x + 15 }));

describe("busiestColumn", () => {
  it("counts the column with the most nodes", () => {
    const nodes = [...column(16, 3), ...column(300, 1), ...column(584.4, 12)];
    assert.equal(busiestColumn(nodes), 12);
    assert.equal(columnCount(nodes), 3);
  });
});

describe("fittedHeight", () => {
  it("keeps the box height for a few categories", () => {
    assert.equal(fittedHeight(4, { baseHeight: 344, margin: 16 }), 344);
  });

  it("grows with a busy column so each gap gets a label's room", () => {
    const height = fittedHeight(20, { baseHeight: 344, margin: 16 });
    assert.ok(height > 344);
    assert.equal(fittedPadding(20, { height, margin: 16 }), TARGET_PADDING);
  });

  it("adds the room set aside for open IOUs", () => {
    const plain = fittedHeight(20, { baseHeight: 344, margin: 16 });
    assert.equal(fittedHeight(20, { baseHeight: 344, margin: 16, reserve: 48 }), plain + 48);
  });
});

describe("fittedPadding", () => {
  it("never drops under the minimum", () => {
    assert.equal(fittedPadding(200, { height: 344, margin: 16 }), 4);
  });
});

describe("fittedWidth", () => {
  it("widens a narrow chart to keep columns apart", () => {
    assert.equal(fittedWidth(3, { baseWidth: 1000, margin: 16, nodeWidth: 15 }), 1000);
    assert.equal(fittedWidth(5, { baseWidth: 340, margin: 16, nodeWidth: 15 }), 32 + 4 * MIN_COLUMN_PITCH + 15);
  });
});

describe("labelRoom", () => {
  const columns = [16, 200, 384];
  it("runs to the next column for a label on the right", () => {
    assert.equal(labelRoom({ x0: 16, x1: 31 }, true, { columns, width: 400 }), 200 - 4 - 37);
  });

  it("runs back to the previous column's bar for a label on the left", () => {
    assert.equal(labelRoom({ x0: 384, x1: 399 }, false, { columns, width: 400 }), 378 - (200 + 15 + 4));
  });

  it("runs to the edge from the outer columns", () => {
    assert.equal(labelRoom({ x0: 384, x1: 399 }, true, { columns, width: 600 }), 598 - 405);
  });
});

describe("fitText", () => {
  const measure = (text) => Array.from(text).length * 10;

  it("leaves a name that fits alone", () => {
    assert.equal(fitText("Rent", 40, measure), "Rent");
  });

  it("cuts a long name with an ellipsis", () => {
    const fitted = fitText("Restaurants and cafes", 80, measure);
    assert.equal(fitted, "Restaur…");
    assert.ok(measure(fitted) <= 80);
  });

  it("gives up when not even a few letters fit", () => {
    assert.equal(fitText("Restaurants", 20, measure), "");
  });
});

describe("rescuedLabelShifts", () => {
  // A parent's label (kept) sits where its one large child's label wants to
  // be: both centred on the same height, in the gap between their columns.
  const parent = { index: 0, value: 100, x0: 300, x1: 315, y0: 0, y1: 200 };
  const child = { index: 1, value: 90, x0: 450, x1: 465, y0: 0, y1: 180 };
  const boxes = new Map([
    [0, { x: 321, y: 85, width: 90, height: 30 }],
    [1, { x: 354, y: 75, width: 90, height: 30 }],
  ]);

  it("moves a hidden label along its tall bar until it is clear", () => {
    const shifts = rescuedLabelShifts([parent, child], boxes, new Set([1]));
    assert.equal(shifts.get(1), 75);
  });

  it("leaves a label hidden when its bar is shorter than the label", () => {
    const short = { ...child, y0: 80, y1: 100 };
    assert.equal(rescuedLabelShifts([parent, short], boxes, new Set([1])).size, 0);
  });

  it("leaves a label hidden when neither end of the bar is clear", () => {
    const crowded = new Map(boxes);
    crowded.set(0, { x: 321, y: 0, width: 130, height: 200 });
    assert.equal(rescuedLabelShifts([parent, child], crowded, new Set([1])).size, 0);
  });

  it("has nothing to do when no label is hidden", () => {
    assert.equal(rescuedLabelShifts([parent, child], boxes, new Set()).size, 0);
  });
});
