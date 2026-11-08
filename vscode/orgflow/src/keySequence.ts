// Pure key-menu logic, kept free of the vscode import so it can be unit-tested.

export interface MenuNode {
  key: string;
  name: string;
  command?: string;
  args?: unknown;
  children?: MenuNode[];
  /** When set, the node only appears in these languages. */
  languages?: string[];
}

export type WalkResult =
  | { kind: "branch"; node: MenuNode }
  | { kind: "leaf"; node: MenuNode; extraKeys: string }
  | { kind: "unknown"; node: MenuNode; badKey: string };

/**
 * Walks typed characters down the menu one at a time. Several characters can
 * arrive in a single input event when typing fast, so they are never assumed
 * to be one keypress.
 */
export function walk(start: MenuNode, typed: string): WalkResult {
  let node = start;
  const chars = Array.from(typed);
  for (let i = 0; i < chars.length; i++) {
    const next = node.children?.find((child) => child.key === chars[i]);
    if (!next) {
      return { kind: "unknown", node, badKey: chars[i] };
    }
    node = next;
    if (!node.children) {
      return { kind: "leaf", node, extraKeys: chars.slice(i + 1).join("") };
    }
  }
  return { kind: "branch", node };
}

/** Copies the tree without nodes that don't apply to a language, or empty groups. */
export function filterMenu(node: MenuNode, language: string | undefined): MenuNode {
  return {
    ...node,
    children: node.children
      ?.filter(
        (child) =>
          !child.languages || (language && child.languages.includes(language)),
      )
      .map((child) => filterMenu(child, language))
      .filter((child) => !child.children || child.children.length > 0),
  };
}

/** Turns flat capture keys such as `w` and `ww` into a menu tree. */
export function treeFromKeys<T extends { key: string; description: string }>(
  items: T[],
  toNode: (item: T) => Partial<MenuNode>,
): MenuNode {
  const root: MenuNode = { key: "", name: "", children: [] };
  for (const item of items) {
    let parent = root;
    const keys = Array.from(item.key);
    keys.slice(0, -1).forEach((key) => {
      let next = parent.children?.find((child) => child.key === key);
      if (!next) {
        next = { key, name: `+${key}`, children: [] };
        parent.children?.push(next);
      }
      next.children ??= [];
      parent = next;
    });
    const key = keys[keys.length - 1];
    const existing = parent.children?.find((child) => child.key === key);
    const node = { key, name: item.description, ...toNode(item) };
    if (existing) {
      Object.assign(existing, node, { children: existing.children });
    } else {
      parent.children?.push(node);
    }
  }
  return root;
}
