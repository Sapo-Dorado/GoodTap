/**
 * Tests for DragDrop hook — pile hotkey behavior and optimistic hiding.
 *
 * We mount the hook with a fake LiveView context (mock pushEvent, real jsdom DOM)
 * and fire synthetic keydown events to verify behavior.
 *
 * The server-side "no lost clicks" guarantee is tested in Elixir
 * (actions_test.exs). Here we verify the client sends the right number of
 * events and does not drop keypresses.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import DragDrop from "./drag_drop.js";

// ─── DOM Helpers ─────────────────────────────────────────────────────────────

function makeCard(instanceId, zone, owner = "host") {
  const el = document.createElement("div");
  el.id = `card-${instanceId}`;
  el.setAttribute("data-draggable", "true");
  el.setAttribute("data-instance-id", instanceId);
  el.setAttribute("data-zone", zone);
  el.setAttribute("data-owner", owner);
  el.setAttribute("data-card-img", "https://example.com/card.jpg");
  el.setAttribute("data-selected", "false");
  el.setAttribute("data-is-token", "false");
  return el;
}

function makePile(zone, instanceId, count = 5) {
  const pile = document.createElement("div");
  pile.setAttribute("data-drop-zone", zone);
  pile.setAttribute("data-pile-zone", zone);

  // Background image (pointer-events none, like production)
  const img = document.createElement("img");
  img.src = "https://example.com/card.jpg";
  img.style.pointerEvents = "none";
  pile.appendChild(img);

  // Transparent overlay (the actual draggable)
  const overlay = document.createElement("div");
  overlay.id = `${zone}-top-${instanceId}`;
  overlay.setAttribute("data-draggable", "true");
  overlay.setAttribute("data-instance-id", instanceId);
  overlay.setAttribute("data-zone", zone);
  overlay.setAttribute("data-owner", "host");
  overlay.setAttribute("data-card-img", "https://example.com/card.jpg");
  pile.appendChild(overlay);

  // Count badge
  const badge = document.createElement("div");
  badge.className = "bg-black/70";
  badge.textContent = String(count);
  pile.appendChild(badge);

  return pile;
}

function makeBattlefield(myRole = "host") {
  const bf = document.createElement("div");
  bf.id = "battlefield";
  bf.setAttribute("data-drop-zone", "battlefield");
  bf.setAttribute("data-my-role", myRole);
  bf.setAttribute("data-move-keys", "g,e,l,L,h,b");
  bf.setAttribute("phx-hook", "DragDrop");
  return bf;
}

// ─── Hook Mounting ────────────────────────────────────────────────────────────

function mountHook(bf) {
  const events = [];
  const hook = Object.create(DragDrop);
  hook.el = bf;
  hook.pushEvent = (name, payload) => events.push({ name, payload });
  hook.handleEvent = () => {};
  hook.mounted();
  return { hook, events };
}

function fireKeydown(key) {
  document.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true }));
}

// ─── Setup / Teardown ─────────────────────────────────────────────────────────

let bf, hook, events;

beforeEach(() => {
  document.body.innerHTML = "";
  bf = makeBattlefield();
  document.body.appendChild(bf);
  ({ hook, events } = mountHook(bf));
});

afterEach(() => {
  if (hook.destroyed) hook.destroyed();
  document.body.innerHTML = "";
  events.length = 0;
});

// ─── Pile Hotkey Tests ────────────────────────────────────────────────────────

describe("pile hotkey — no clicks lost", () => {
  it("pressing 'h' 5× while hovering graveyard pile sends 5 hotkey events", () => {
    const pile = makePile("graveyard", "gy-card-1", 5);
    bf.appendChild(pile);

    // Simulate hovering the graveyard pile overlay
    const overlay = pile.querySelector("[data-instance-id]");
    bf.dispatchEvent(new MouseEvent("mouseover", { bubbles: true, target: overlay, relatedTarget: null }));
    // Set hoveredCard directly (mouseover handler sets it via closest())
    hook.hoveredCard = {
      instanceId: "gy-card-1",
      zone: "graveyard",
      owner: "host"
    };

    for (let i = 0; i < 5; i++) {
      fireKeydown("h");
    }

    const hotkeyEvents = events.filter(e => e.name === "hotkey");
    expect(hotkeyEvents).toHaveLength(5);
    // All events should reference the graveyard zone
    expect(hotkeyEvents.every(e => e.payload.zone === "graveyard")).toBe(true);
  });

  it("pressing 'e' 5× while hovering exile pile sends 5 hotkey events", () => {
    const pile = makePile("exile", "ex-card-1", 5);
    bf.appendChild(pile);

    hook.hoveredCard = { instanceId: "ex-card-1", zone: "exile", owner: "host" };

    for (let i = 0; i < 5; i++) {
      fireKeydown("e");
    }

    const hotkeyEvents = events.filter(e => e.name === "hotkey");
    expect(hotkeyEvents).toHaveLength(5);
    expect(hotkeyEvents.every(e => e.payload.zone === "exile")).toBe(true);
  });

  it("pressing 'h' 5× while hovering deck pile sends 5 hotkey events", () => {
    const pile = makePile("deck", "deck-card-1", 40);
    bf.appendChild(pile);

    hook.hoveredCard = { instanceId: "deck-card-1", zone: "deck", owner: "host" };

    for (let i = 0; i < 5; i++) {
      fireKeydown("h");
    }

    const hotkeyEvents = events.filter(e => e.name === "hotkey");
    expect(hotkeyEvents).toHaveLength(5);
  });

  it("each hotkey event carries the correct instance_id from hoveredCard", () => {
    const pile = makePile("graveyard", "gy-abc", 3);
    bf.appendChild(pile);

    hook.hoveredCard = { instanceId: "gy-abc", zone: "graveyard", owner: "host" };
    fireKeydown("h");

    const ev = events.find(e => e.name === "hotkey");
    expect(ev.payload.instance_id).toBe("gy-abc");
    expect(ev.payload.zone).toBe("graveyard");
    expect(ev.payload.owner).toBe("host");
  });
});

// ─── Optimistic Hide Tests ────────────────────────────────────────────────────

describe("optimisticallyHideCard — pile zones are NOT hidden", () => {
  it("pressing a move key on a graveyard pile does NOT hide the pile overlay", () => {
    const pile = makePile("graveyard", "gy-card-1", 5);
    bf.appendChild(pile);
    const overlay = pile.querySelector("[data-instance-id]");

    hook.hoveredCard = { instanceId: "gy-card-1", zone: "graveyard", owner: "host" };
    fireKeydown("h");

    // Overlay should remain visible (not hidden optimistically)
    expect(overlay.style.visibility).not.toBe("hidden");
  });

  it("pressing a move key on an exile pile does NOT hide the pile overlay", () => {
    const pile = makePile("exile", "ex-card-1", 5);
    bf.appendChild(pile);
    const overlay = pile.querySelector("[data-instance-id]");

    hook.hoveredCard = { instanceId: "ex-card-1", zone: "exile", owner: "host" };
    fireKeydown("e");

    expect(overlay.style.visibility).not.toBe("hidden");
  });

  it("pressing a move key on a battlefield card DOES hide it optimistically", () => {
    const cardEl = makeCard("bf-card-1", "battlefield");
    bf.appendChild(cardEl);

    hook.hoveredCard = { instanceId: "bf-card-1", zone: "battlefield", owner: "host" };
    fireKeydown("g");

    // Battlefield card should be hidden immediately
    expect(cardEl.style.visibility).toBe("hidden");
  });

  it("pressing a move key on a hand card DOES hide it optimistically", () => {
    const handCard = document.createElement("div");
    handCard.id = "hand-card-hand1";
    handCard.setAttribute("data-instance-id", "hand1");
    handCard.setAttribute("data-zone", "hand");
    handCard.setAttribute("data-owner", "host");
    document.body.appendChild(handCard);

    hook.hoveredCard = { instanceId: "hand1", zone: "hand", owner: "host" };
    fireKeydown("g");

    expect(handCard.style.visibility).toBe("hidden");
  });
});

// ─── Non-move keys do not hide cards ─────────────────────────────────────────

describe("non-move keys", () => {
  it("pressing 't' (tap) on a battlefield card does not hide it", () => {
    const cardEl = makeCard("bf-card-2", "battlefield");
    bf.appendChild(cardEl);

    hook.hoveredCard = { instanceId: "bf-card-2", zone: "battlefield", owner: "host" };
    fireKeydown("t");

    expect(cardEl.style.visibility).not.toBe("hidden");
    // But event is still sent
    const ev = events.find(e => e.name === "hotkey" && e.payload.key === "t");
    expect(ev).toBeDefined();
  });
});

// ─── Opponent cards are not acted on ─────────────────────────────────────────

describe("opponent card protection", () => {
  it("move key with opponent card as hovered does not hide anything", () => {
    const cardEl = makeCard("opp-card-1", "battlefield", "opponent");
    bf.appendChild(cardEl);

    hook.hoveredCard = { instanceId: "opp-card-1", zone: "battlefield", owner: "opponent" };
    fireKeydown("g");

    expect(cardEl.style.visibility).not.toBe("hidden");
  });
});
