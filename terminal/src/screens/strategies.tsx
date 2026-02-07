import { Box, Text } from "ink";
import { DetailView } from "../components/detail-view.js";
import { NavigableList } from "../components/navigable-list.js";
import { usd } from "../lib/format.js";
import { colors } from "../lib/theme.js";
import { timeAgo } from "../lib/time.js";
import { useTerminal } from "../store/index.js";
import type { StrategyEntry } from "../store/types.js";

function renderItem(item: StrategyEntry, _index: number, selected: boolean) {
  return (
    <Box>
      <Text bold={selected} color={selected ? colors.textBright : colors.text}>
        {item.name}
      </Text>
      {item.lastEvaluatedAt && (
        <Text color={colors.textDim}>
          {" · evaluated "}
          {timeAgo(item.lastEvaluatedAt)}
        </Text>
      )}
      <Text color={item.dayGainLoss >= 0 ? colors.green : colors.red}>
        {" · "}
        {usd(item.dayGainLoss)}
      </Text>
      <Text color={colors.textDim}>
        {" · "}
        {item.positionCount} pos
      </Text>
    </Box>
  );
}

export function StrategiesScreen() {
  const strategies = useTerminal((s) => s.strategies);
  const viewMode = useTerminal((s) => s.viewMode);
  const selectedIndex = useTerminal((s) => s.selectedIndex);
  const scrollOffset = useTerminal((s) => s.scrollOffset);

  if (viewMode === "detail" && strategies[selectedIndex]) {
    const entry = strategies[selectedIndex];
    return (
      <DetailView
        content={entry.content}
        scrollOffset={scrollOffset}
        title={entry.name}
      />
    );
  }

  return (
    <Box flexDirection="column" flexGrow={1}>
      <Box paddingX={1}>
        <Text bold color={colors.textBright}>
          Strategies
        </Text>
        <Text color={colors.textDim}>
          {" · "}
          {strategies.length} total
        </Text>
      </Box>
      <NavigableList
        emptyMessage="No strategies. Add markdown files to ~/.northbrook/workspace/strategies/"
        items={strategies}
        renderItem={renderItem}
        selectedIndex={selectedIndex}
      />
    </Box>
  );
}
