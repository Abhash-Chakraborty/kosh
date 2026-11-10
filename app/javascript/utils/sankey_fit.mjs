// Sizing for the cash flow Sankey, so labels have room however many
// categories a period has. Padding is worked out from the busiest column
// rather than the node count, the chart grows taller when that column needs
// it, and narrow screens get a minimum column spacing (the chart then
// scrolls sideways) with long names cut to fit.

// Gap between two nodes in a column: about a two-line label, so neighbours
// keep both labels.
export const TARGET_PADDING = 26;
// At most this share of a column's height goes to gaps; the rest shows money.
const PADDING_SHARE = 0.65;
// Closest two columns may sit before the chart is made wider than its box.
export const MIN_COLUMN_PITCH = 92;

// Node count of the busiest column of a laid-out graph.
export function busiestColumn(nodes) {
  const counts = new Map();
  nodes.forEach((node) => {
    const x = Math.round(node.x0);
    counts.set(x, (counts.get(x) || 0) + 1);
  });
  return Math.max(0, ...counts.values());
}

export function columnCount(nodes) {
  return new Set(nodes.map((node) => Math.round(node.x0))).size;
}

// Chart height: the box's height, or more when the busiest column needs it.
export function fittedHeight(count, { baseHeight, margin, reserve = 0 }) {
  const gaps = Math.max(count - 1, 0);
  const graph = Math.ceil((gaps * TARGET_PADDING) / PADDING_SHARE);
  return Math.max(baseHeight, graph + margin * 2 + reserve);
}

// Gap between nodes for a chart of this height.
export function fittedPadding(count, { height, margin, reserve = 0, min = 4 }) {
  const available = height - margin * 2 - reserve;
  const gaps = Math.max(count - 1, 1);
  const padding = Math.floor((available * PADDING_SHARE) / gaps);
  return Math.max(min, Math.min(TARGET_PADDING, padding));
}

// Chart width: the box's width, or enough for every column to keep
// MIN_COLUMN_PITCH apart.
export function fittedWidth(columns, { baseWidth, margin, nodeWidth }) {
  const needed =
    margin * 2 + Math.max(columns - 1, 0) * MIN_COLUMN_PITCH + nodeWidth;
  return Math.max(baseWidth, needed);
}

// Horizontal room for a label beside its node: up to the next column in the
// direction it faces, or the chart's edge.
export function labelRoom(node, onRight, { columns, width }) {
  const gap = 6;
  const clearance = 4;
  if (onRight) {
    const next = columns.find((x) => x > Math.round(node.x0));
    const limit = next === undefined ? width - 2 : next - clearance;
    return Math.max(0, limit - (node.x1 + gap));
  }
  const previous = columns.filter((x) => x < Math.round(node.x0)).pop();
  const limit = previous === undefined ? 2 : previous + (node.x1 - node.x0) + clearance;
  return Math.max(0, node.x0 - gap - limit);
}

// The longest start of `text` that, with an ellipsis, measures within
// `room`. Returns the text unchanged when it fits, and "" when not even a
// few characters do.
export function fitText(text, room, measure, minChars = 3) {
  if (measure(text) <= room) return text;
  const chars = Array.from(text);
  let low = minChars;
  let high = chars.length - 1;
  let best = "";
  while (low <= high) {
    const mid = Math.floor((low + high) / 2);
    const candidate = `${chars.slice(0, mid).join("").trimEnd()}…`;
    if (measure(candidate) <= room) {
      best = candidate;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return best;
}
