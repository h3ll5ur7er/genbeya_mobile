/**
 * The kit's side of the channel to its host: the host defines
 * `window.genbeyaKitHost.post(text)` before the kit loads; the kit defines
 * `window.genbeyaKit.receive(text)`. Messages are JSON strings, so any web
 * view can carry them.
 */
import { parseToKit, type FromKit, type KitRequest, type ToKit } from "./protocol";

declare global {
  interface Window {
    genbeyaKitHost?: { post(message: string): void };
    genbeyaKit?: { receive(message: string): void };
  }
}

type RequestOf<T extends KitRequest["type"]> = Omit<Extract<KitRequest, { type: T }>, "id"> & { type: T };

export class Bridge {
  private next = 0;
  private readonly pending = new Map<number, { resolve(value: string): void; reject(error: Error): void }>();
  /** Messages posted before the host defined its side, sent once it has. */
  private readonly queue: string[] = [];
  private waiting = 0;

  constructor(receive: (message: Exclude<ToKit, { type: "reply" }>) => void) {
    window.genbeyaKit = {
      receive: (text: string) => {
        let message: ToKit;
        try {
          message = parseToKit(text);
        } catch (error) {
          this.post({ type: "error", message: error instanceof Error ? error.message : String(error) });
          return;
        }
        if (message.type !== "reply") return receive(message);
        const request = this.pending.get(message.id);
        this.pending.delete(message.id);
        if (message.error !== undefined) request?.reject(new Error(message.error));
        else request?.resolve(message.value ?? "");
      },
    };
  }

  post(message: Exclude<FromKit, KitRequest>): void {
    this.send(JSON.stringify(message));
  }

  /** Asks the host for an image, a file or the plan's history; resolves to its reply. */
  request<T extends KitRequest["type"]>(request: RequestOf<T>): Promise<string> {
    const id = ++this.next;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.send(JSON.stringify({ ...request, id }));
    });
  }

  private send(text: string) {
    const host = window.genbeyaKitHost;
    if (host && this.queue.length === 0) return host.post(text);
    this.queue.push(text);
    this.flush();
  }

  /** Retries for a few seconds when the host's side isn't there yet. */
  private flush() {
    const host = window.genbeyaKitHost;
    if (host) {
      while (this.queue.length) host.post(this.queue.shift()!);
      return;
    }
    if (this.waiting++ < 100) setTimeout(() => this.flush(), 50);
  }
}
