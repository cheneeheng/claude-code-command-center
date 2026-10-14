import { useCallback, useState } from 'react';

import { ApiRequestError, apiClient } from '../lib/api';

/** Runs an export on the server, then calls `onDone` so the page refetches. */
export function useRefresh(onDone: () => void) {
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | undefined>(undefined);

  const run = useCallback(async () => {
    setBusy(true);
    setMessage(undefined);
    try {
      await apiClient.refresh();
      onDone();
    } catch (e: unknown) {
      if (e instanceof ApiRequestError && e.status === 409) {
        setMessage('Export already running, try again shortly.');
      } else {
        setMessage(`Refresh failed: ${e instanceof Error ? e.message : String(e)}`);
      }
    } finally {
      setBusy(false);
    }
  }, [onDone]);

  return { busy, message, run };
}
