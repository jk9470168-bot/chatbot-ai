const panel = document.querySelector("#chat-panel");
const toggle = document.querySelector("#chat-toggle");
const closeButton = document.querySelector("#chat-close");
const form = document.querySelector("#chat-form");
const input = document.querySelector("#chat-input");
const messagesElement = document.querySelector("#chat-messages");
const sendButton = form.querySelector("button[type='submit']");
const conversation = [];

function setChatOpen(isOpen) {
  panel.hidden = !isOpen;
  toggle.setAttribute("aria-expanded", String(isOpen));
  toggle.setAttribute("aria-label", isOpen ? "Close chat" : "Open chat");
  if (isOpen) input.focus();
}

function addMessage(content, role, isError = false) {
  const message = document.createElement("p");
  message.className = `chat-message ${role === "user" ? "user-message" : "assistant-message"}`;
  if (isError) message.classList.add("is-error");
  message.textContent = content;
  messagesElement.append(message);
  messagesElement.scrollTop = messagesElement.scrollHeight;
  return message;
}

function getRecentConversation(maxBytes = 14000) {
  const recent = [];

  for (let index = conversation.length - 1; index >= 0 && recent.length < 10; index -= 1) {
    const message = conversation[index];
    const content = message.content.slice(0, 2000);
    recent.unshift({ role: message.role, content });
  }

  const encoder = new TextEncoder();
  while (recent.length > 1 && encoder.encode(JSON.stringify({ messages: recent })).length > maxBytes) {
    recent.shift();
  }
  return recent;
}

toggle.addEventListener("click", () => setChatOpen(panel.hidden));
closeButton.addEventListener("click", () => setChatOpen(false));

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const content = input.value.trim();
  if (!content || sendButton.disabled) return;

  if (conversation.length > 10) conversation.splice(0, conversation.length - 10);
  conversation.push({ role: "user", content });
  addMessage(content, "user");
  input.value = "";
  sendButton.disabled = true;
  sendButton.setAttribute("aria-label", "Sending message");

  try {
    const response = await fetch("/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ messages: getRecentConversation() }),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "Unable to get a response.");
    conversation.push({ role: "assistant", content: result.reply });
    addMessage(result.reply, "assistant");
  } catch (error) {
    conversation.pop();
    addMessage(error.message || "Couldn't reach the assistant. Please try again.", "assistant", true);
  } finally {
    sendButton.disabled = false;
    sendButton.setAttribute("aria-label", "Send message");
    input.focus();
  }
});