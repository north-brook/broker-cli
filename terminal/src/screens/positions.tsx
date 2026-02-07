import { Box, Text } from "ink";
import { Badge } from "../components/badge.js";
import { DetailView } from "../components/detail-view.js";
import { NavigableList } from "../components/navigable-list.js";
import { num, usd } from "../lib/format.js";
import { colors } from "../lib/theme.js";
import { useTerminal } from "../store/index.js";
import type { PositionEntry } from "../store/types.js";

function renderItem(item: PositionEntry, _index: number, selected: boolean) {
  const hasBrokerData = item.qty > 0 || item.status === "open";
  return (
    <Box>
      <Text bold={selected} color={selected ? colors.textBright : colors.text}>
        {item.symbol}
      </Text>
      <Text color={colors.textDim}>
        {" · "}
        {hasBrokerData ? `${num(item.qty, 0)} shares` : "--"}
        {" · "}
        {hasBrokerData ? usd(item.marketValue) : "--"}
      </Text>
      {hasBrokerData && item.unrealizedPnl != null && (
        <Text color={item.unrealizedPnl >= 0 ? colors.green : colors.red}>
          {" · "}
          {usd(item.unrealizedPnl)}
        </Text>
      )}
      <Text> </Text>
      <Badge
        label={item.status}
        variant={item.status === "open" ? "success" : "muted"}
      />
    </Box>
  );
}

export function PositionsScreen() {
  const positions = useTerminal((s) => s.positions);
  const viewMode = useTerminal((s) => s.viewMode);
  const selectedIndex = useTerminal((s) => s.selectedIndex);
  const scrollOffset = useTerminal((s) => s.scrollOffset);

  if (viewMode === "detail" && positions[selectedIndex]) {
    const entry = positions[selectedIndex];
    return (
      <DetailView
        content={entry.content}
        scrollOffset={scrollOffset}
        title={entry.symbol}
      />
    );
  }

  return (
    <Box flexDirection="column" flexGrow={1}>
      <Box paddingX={1}>
        <Text bold color={colors.textBright}>
          Positions
        </Text>
        <Text color={colors.textDim}>
          {" · "}
          {positions.length} total
        </Text>
      </Box>
      <NavigableList
        emptyMessage="No positions. Add markdown files to ~/.northbrook/workspace/positions/"
        items={positions}
        renderItem={renderItem}
        selectedIndex={selectedIndex}
      />
    </Box>
  );
}
