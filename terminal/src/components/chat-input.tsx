import { Box, Text } from "ink";
import TextInput from "ink-text-input";
import { colors } from "../lib/theme.js";
import { useTerminal } from "../store/index.js";

export function ChatInput() {
  const chatInput = useTerminal((s) => s.chatInput);
  const chatFocused = useTerminal((s) => s.chatFocused);
  const setChatInput = useTerminal((s) => s.setChatInput);
  const submitChat = useTerminal((s) => s.submitChat);

  return (
    <Box paddingX={1}>
      <Text color={chatFocused ? colors.brand : colors.textDim}>{"> "}</Text>
      <TextInput
        focus={chatFocused}
        onChange={setChatInput}
        onSubmit={() => {
          if (chatInput.trim()) {
            submitChat();
          }
        }}
        placeholder={chatFocused ? "Type a message..." : ""}
        value={chatInput}
      />
    </Box>
  );
}
