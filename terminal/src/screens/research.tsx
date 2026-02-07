import { Box, Text } from "ink";
import { DetailView } from "../components/detail-view.js";
import { NavigableList } from "../components/navigable-list.js";
import { colors } from "../lib/theme.js";
import { timeAgo } from "../lib/time.js";
import { useTerminal } from "../store/index.js";
import type { ResearchEntry } from "../store/types.js";

function renderItem(item: ResearchEntry, _index: number, selected: boolean) {
  return (
    <Box>
      <Text bold={selected} color={selected ? colors.textBright : colors.text}>
        {item.title}
      </Text>
      {item.completedAt && (
        <Text color={colors.textDim}>
          {" · completed "}
          {timeAgo(item.completedAt)}
        </Text>
      )}
      {item.tags.length > 0 && (
        <Text color={colors.brand}>
          {" · "}
          {item.tags.join(", ")}
        </Text>
      )}
    </Box>
  );
}

export function ResearchScreen() {
  const research = useTerminal((s) => s.research);
  const viewMode = useTerminal((s) => s.viewMode);
  const selectedIndex = useTerminal((s) => s.selectedIndex);
  const scrollOffset = useTerminal((s) => s.scrollOffset);

  if (viewMode === "detail" && research[selectedIndex]) {
    const entry = research[selectedIndex];
    return (
      <DetailView
        content={entry.content}
        scrollOffset={scrollOffset}
        title={entry.title}
      />
    );
  }

  return (
    <Box flexDirection="column" flexGrow={1}>
      <Box paddingX={1}>
        <Text bold color={colors.textBright}>
          Research
        </Text>
        <Text color={colors.textDim}>
          {" · "}
          {research.length} total
        </Text>
      </Box>
      <NavigableList
        emptyMessage="No research. Add markdown files to ~/.northbrook/workspace/research/"
        items={research}
        renderItem={renderItem}
        selectedIndex={selectedIndex}
      />
    </Box>
  );
}
