/**
 * Send a NUI callback to the Lua client
 */
export async function fetchNui<T = any>(event: string, data?: any): Promise<T> {
  try {
    const resp = await fetch(`https://retry_greenscreener/${event}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data ?? {}),
    });
    return resp.json();
  } catch (e) {
    console.error(`[NUI] fetchNui failed for "${event}":`, e);
    return undefined as T;
  }
}

/**
 * Register a listener for NUI messages from Lua
 */
export function onNuiMessage<T = any>(action: string, handler: (data: T) => void): void {
  window.addEventListener('message', (event: MessageEvent) => {
    if (event.data?.action === action) {
      handler(event.data.data);
    }
  });
}
