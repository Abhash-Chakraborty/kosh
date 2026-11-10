// Open IOUs on the cash flow chart: money that hasn't moved yet. Money owed
// to the family sits in the column income flows in from, money it owes in
// the column spending flows out to, below the real nodes. Each has a faded,
// dashed pipe that heads for Cash Flow and stops short of it. They take no
// part in d3-sankey's layout, so no node size, total or percentage changes
// because of them.

// Height of one pending row: room for a three-line label (name, amount,
// "not received") and a gap.
export const PENDING_SLOT = 48;
const MIN_BAR = 6;
const MAX_BAR = 24;
// Space between the lowest real node (and its label) and the first row.
const GAP = 12;
// The pipe is a short stub towards Cash Flow: this share of the way to the
// next column, at most MAX_PIPE px, bending towards it by at most MAX_RISE
// px. The label sits where the pipe breaks off, clear of the stub.
const PIPE_REACH = 0.35;
const MAX_PIPE = 44;
const MAX_RISE = 8;

export const PENDING_COLORS = {
  owed_to_me: "var(--color-success)",
  i_owe: "var(--color-destructive)",
};

const isIncoming = (flow) => flow.direction === "owed_to_me";

// Vertical space the chart sets aside under its graph for the pending rows.
export function pendingReserve(pending) {
  if (!pending?.length) return 0;
  const incoming = pending.filter(isIncoming).length;
  const rows = Math.max(incoming, pending.length - incoming);
  return GAP + rows * PENDING_SLOT;
}

// Places each pending flow beside the laid-out graph. Returns copies with
// bar coordinates (x0, x1, y0, y1), the label side and the pipe's path.
export function layoutPendingFlows(nodes, pending, { nodeWidth }) {
  if (!pending?.length || !nodes?.length) return [];

  const hubs = nodes.filter(
    (node) => node.kind === "cash_flow" || node.kind === "account",
  );
  if (!hubs.length) return [];
  const hubX = Math.round(hubs[0].x0);
  const columns = [...new Set(nodes.map((node) => Math.round(node.x0)))].sort(
    (a, b) => a - b,
  );
  const before = columns.filter((x) => x < hubX).pop();
  const after = columns.find((x) => x > hubX);

  // Pixels per unit, from the largest real node, so a pending bar reads on
  // the same scale until it hits the clamp.
  const largest = nodes.reduce((a, b) => (b.value > a.value ? b : a));
  const scale = largest.value > 0 ? (largest.y1 - largest.y0) / largest.value : 0;

  const bottomOf = (x) =>
    Math.max(
      ...nodes
        .filter((node) => Math.round(node.x0) === x)
        .map((node) => Math.max(node.y1, (node.y0 + node.y1) / 2 + 16)),
    );
  // The hub's lowest point, where an unconnected pipe would have joined.
  const hub = hubs.reduce((a, b) => (b.y1 > a.y1 ? b : a));

  const placed = [];
  for (const incoming of [true, false]) {
    const flows = pending.filter((flow) => isIncoming(flow) === incoming);
    if (!flows.length) continue;

    const column = incoming ? before : after;
    const x0 = column ?? hubX;
    const top = bottomOf(x0) + GAP;

    flows.forEach((flow, row) => {
      const bar = Math.min(MAX_BAR, Math.max(MIN_BAR, flow.value * scale));
      const mid = top + row * PENDING_SLOT + PENDING_SLOT / 2;
      const node = {
        ...flow,
        color: PENDING_COLORS[flow.direction],
        x0,
        x1: x0 + nodeWidth,
        y0: mid - bar / 2,
        y1: mid + bar / 2,
        labelOnRight: incoming,
        pipe: null,
        pipeWidth: Math.max(2, bar - 2),
      };
      // Without a column on that side there is nowhere for a pipe to run.
      if (column !== undefined) {
        const gap = incoming ? hub.x0 - node.x1 : node.x0 - hub.x1;
        const length = Math.min(MAX_PIPE, gap * PIPE_REACH);
        const rise = Math.max(-MAX_RISE, Math.min(MAX_RISE, hub.y1 - mid));
        node.pipe = incoming
          ? linkPath({ x: node.x1, y: mid }, { x: node.x1 + length, y: mid + rise })
          : linkPath({ x: node.x0 - length, y: mid + rise }, { x: node.x0, y: mid });
        node.labelX = incoming ? node.x1 + length + 6 : node.x0 - length - 6;
        node.room = Math.max(0, gap - length - 10);
      } else {
        node.labelX = incoming ? node.x1 + 6 : node.x0 - 6;
        node.room = 120;
      }
      placed.push(node);
    });
  }
  return placed;
}

// d3.linkHorizontal's curve between two points, as an SVG path.
export function linkPath(source, target) {
  const midX = (source.x + target.x) / 2;
  const f = (x, y) => `${round(x)},${round(y)}`;
  return `M${f(source.x, source.y)}C${f(midX, source.y)},${f(midX, target.y)},${f(target.x, target.y)}`;
}

const round = (n) => Math.round(n * 10) / 10;

// Draws the placed flows into the chart's SVG. Each is one link to the Owed
// page: Enter or a click opens it.
// `fit` is sankey_fit's fitText, passed in so this module needs no import
// (importmap names don't resolve under Node's test runner).
export function drawPendingFlows(svg, flows, { format, fit, onActivate }) {
  if (!flows.length) return null;

  const items = svg
    .append("g")
    .attr("class", "sankey-pending")
    .selectAll("g")
    .data(flows)
    .join("g")
    .attr("data-pending-id", (d) => d.id)
    .attr("role", "link")
    .attr("tabindex", 0)
    .attr("aria-label", (d) => `${d.description}, ${format(d.value)}, ${d.note}`)
    .style("cursor", "pointer")
    .on("click", (event, d) => {
      event.stopPropagation();
      onActivate(d);
    })
    .on("keydown", (event, d) => {
      if (!["Enter", " "].includes(event.key)) return;
      event.preventDefault();
      event.stopPropagation();
      onActivate(d);
    });

  items.append("title").text((d) => d.description);

  const pipes = items.filter((d) => d.pipe);
  pipes
    .append("path")
    .attr("class", "sankey-pending-pipe")
    .attr("d", (d) => d.pipe)
    .attr("fill", "none")
    .attr("stroke-width", (d) => d.pipeWidth)
    .style("stroke", (d) => d.color)
    .style("stroke-opacity", 0.12);
  pipes
    .append("path")
    .attr("d", (d) => d.pipe)
    .attr("fill", "none")
    .attr("stroke-width", 1.5)
    .attr("stroke-dasharray", "4 3")
    .style("stroke", (d) => d.color)
    .style("stroke-opacity", 0.6);

  items
    .append("rect")
    .attr("x", (d) => d.x0)
    .attr("y", (d) => d.y0)
    .attr("width", (d) => d.x1 - d.x0)
    .attr("height", (d) => d.y1 - d.y0)
    .attr("rx", 3)
    .attr("stroke-dasharray", "3 2")
    .style("fill", (d) => d.color)
    .style("fill-opacity", 0.15)
    .style("stroke", (d) => d.color)
    .style("stroke-opacity", 0.7);

  const x = (d) => d.labelX;
  const text = items
    .append("text")
    .attr("class", "text-xs text-secondary fill-current select-none")
    .attr("x", x)
    .attr("y", (d) => (d.y0 + d.y1) / 2)
    .attr("dy", "-0.9em")
    .attr("text-anchor", (d) => (d.labelOnRight ? "start" : "end"));
  text
    .append("tspan")
    .attr("class", "font-medium")
    .each(function (d) {
      // Cut to the gap beside the bar, like the graph's own labels.
      this.textContent = fit(d.name, d.room, (candidate) => {
        this.textContent = candidate;
        return this.getComputedTextLength();
      }) || d.name.slice(0, 1);
    });
  text
    .append("tspan")
    .attr("x", x)
    .attr("dy", "1.2em")
    .attr("class", "font-mono")
    .style("font-size", "0.7rem")
    .text((d) => format(d.value));
  text
    .append("tspan")
    .attr("x", x)
    .attr("dy", "1.2em")
    .style("font-size", "0.7rem")
    .text((d) => d.note);

  return items;
}
