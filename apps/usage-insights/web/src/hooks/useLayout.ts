import { useCallback, useEffect, useState } from 'react';

import { type Layout, parseLayout, toLayout } from '../layout/model';
import { apiClient } from '../lib/api';

/**
 * The saved layout, else the default. `saved` is `undefined` while loading and `null`
 * when nothing is saved; an unreadable answer counts as nothing saved.
 */
export function useLayout() {
  const [saved, setSaved] = useState<Layout | null | undefined>(undefined);
  const [message, setMessage] = useState<string | undefined>(undefined);

  useEffect(() => {
    let active = true;
    apiClient
      .getLayout()
      .then((raw) => active && setSaved(parseLayout(raw)))
      .catch(() => active && setSaved(null));
    return () => {
      active = false;
    };
  }, []);

  const reset = useCallback(async () => {
    try {
      await apiClient.deleteLayout();
      setSaved(null);
      setMessage(undefined);
    } catch {
      setMessage('Could not reset the layout');
    }
  }, []);

  return { saved, layout: saved ?? toLayout(), loading: saved === undefined, message, reset };
}
