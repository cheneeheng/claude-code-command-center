import { type FormEvent, useState } from 'react';

import type { Chat } from '../hooks/useAgent';

const STARTERS = [
  'Which projects cost more than last month?',
  'Show my daily cost this month',
  'Which skills do I use most?',
];

/** Props of {@link ChatDrawer}. */
export type ChatDrawerProps = {
  chat: Chat;
  /** Shown when saving an edit failed; the edit stays on screen. */
  saveError?: string;
  onClose: () => void;
};

/** The chat beside the dashboard: ask a question, and the agent places panels. */
export function ChatDrawer({ chat, saveError, onClose }: ChatDrawerProps) {
  const [text, setText] = useState('');

  function submit(e: FormEvent) {
    e.preventDefault();
    const message = text.trim();
    if (!message || chat.running) return;
    setText('');
    void chat.send(message);
  }

  return (
    <aside className="drawer card" aria-label="Chat">
      <div className="drawer-head">
        <h2 className="drawer-title">Chat</h2>
        <button type="button" className="btn btn-ghost btn-sm" onClick={chat.newChat}>
          New chat
        </button>
        <button type="button" className="btn btn-ghost btn-sm" onClick={onClose}>
          Close
        </button>
      </div>
      <ol className="chat-lines" aria-live="polite">
        {chat.lines.map((line) => (
          <li key={line.id} className={`chat-line chat-${line.kind}`}>
            {line.text}
          </li>
        ))}
      </ol>
      {chat.lines.length === 0 && (
        <div className="chat-starters">
          <p className="muted">Ask about your usage. The answer arrives as panels on the dashboard.</p>
          {STARTERS.map((s) => (
            <button key={s} type="button" className="btn btn-outline btn-sm" onClick={() => void chat.send(s)}>
              {s}
            </button>
          ))}
        </div>
      )}
      {chat.running && (
        <p className="muted" role="status">
          <span className="spinner" aria-hidden="true" /> Working…
        </p>
      )}
      {chat.error && !chat.running && (
        <p className="text-danger" role="alert">
          {chat.error}{' '}
          <button type="button" className="btn btn-ghost btn-sm" onClick={() => void chat.retry()}>
            Retry
          </button>
        </p>
      )}
      {saveError && <p className="text-warning">{saveError}</p>}
      <form className="chat-form" onSubmit={submit}>
        <input
          className="input"
          aria-label="Message"
          placeholder="Ask a question"
          value={text}
          onChange={(e) => setText(e.target.value)}
          disabled={chat.running}
        />
        <button type="submit" className="btn btn-primary" disabled={chat.running}>
          Send
        </button>
        {chat.running && (
          <button type="button" className="btn btn-outline" onClick={chat.stop}>
            Stop
          </button>
        )}
      </form>
    </aside>
  );
}
