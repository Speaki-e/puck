import { EventEmitter } from "node:events";
import type { BridgeMessage } from "@speaki-e/protocol";

export class MockPetApp extends EventEmitter {
  readonly received: BridgeMessage[] = [];

  receive(message: BridgeMessage): void {
    this.received.push(message);
    this.emit("message", message);
  }
}
