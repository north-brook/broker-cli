import { Box, Text } from "ink";
import { colors } from "../lib/theme.js";
import { useTerminal } from "../store/index.js";

export function ChatView() {
  const session = useTerminal((s) => s.activeSession);

  if (!session) {
    return (
      <Box paddingX={1}>
        <Text color={colors.textDim}>No active chat session.</Text>
      </Box>
    );
  }

  return (
    <Box flexDirection="column" flexGrow={1} paddingX={1}>
      <Box>
        <Text bold color={colors.textBright}>
          Chat Session
        </Text>
        <Text color={colors.textDim}> on {session.originScreen}</Text>
        <Box flexGrow={1} />
        <Text color={colors.textMuted}>esc to exit</Text>
      </Box>
      <Text color={colors.border}>{"─".repeat(60)}</Text>

      <Box flexDirection="column" flexGrow={1} paddingTop={1}>
        {session.messages.map((msg) => (
          <Box key={msg.id} paddingBottom={1}>
            <Text color={msg.role === "user" ? colors.text : colors.brand}>
              {msg.role === "user" ? "You" : "NB"}
            </Text>
            <Text color={colors.textDim}>{" · "}</Text>
            <Text
              color={msg.role === "user" ? colors.text : colors.brand}
              wrap="wrap"
            >
              {msg.content}
            </Text>
          </Box>
        ))}
      </Box>
    </Box>
  );
}
