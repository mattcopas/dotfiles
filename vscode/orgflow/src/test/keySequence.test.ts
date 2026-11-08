import assert from "node:assert/strict";
import { test } from "node:test";
import { filterMenu, MenuNode, treeFromKeys, walk } from "../keySequence";

const root: MenuNode = {
  key: "",
  name: "root",
  children: [
    {
      key: "p",
      name: "project",
      children: [
        { key: "p", name: "switch" },
        { key: "b", name: "buffer" },
      ],
    },
    { key: "w", name: "save" },
    { key: " ", name: "find" },
    {
      key: "m",
      name: "local",
      languages: ["org"],
      children: [{ key: "t", name: "todo" }],
    },
  ],
};

test("one key into a submenu stays on that branch", () => {
  const result = walk(root, "p");
  assert.equal(result.kind, "branch");
  assert.equal(result.node.name, "project");
});

test("keys arriving together in one event reach the leaf", () => {
  const result = walk(root, "pp");
  assert.equal(result.kind, "leaf");
  assert.equal(result.node.name, "switch");
});

test("space is a normal menu key", () => {
  const result = walk(root, " ");
  assert.equal(result.kind, "leaf");
  assert.equal(result.node.name, "find");
});

test("the walk can resume from a submenu", () => {
  const project = root.children![0];
  const result = walk(project, "b");
  assert.equal(result.kind, "leaf");
  assert.equal(result.node.name, "buffer");
});

test("keys after a leaf are reported rather than lost", () => {
  const result = walk(root, "wxy");
  assert.deepEqual(result.kind === "leaf" && result.extraKeys, "xy");
});

test("an unbound key is reported with the node it failed on", () => {
  const result = walk(root, "pz");
  assert.equal(result.kind, "unknown");
  assert.equal(result.node.name, "project");
  assert.equal(result.kind === "unknown" && result.badKey, "z");
});

test("empty input stays where it started", () => {
  const result = walk(root, "");
  assert.equal(result.kind, "branch");
  assert.equal(result.node, root);
});

test("language-only nodes appear only in that language", () => {
  const keys = (language?: string) =>
    filterMenu(root, language).children?.map((child) => child.key);
  assert.deepEqual(keys("org"), ["p", "w", " ", "m"]);
  assert.deepEqual(keys("python"), ["p", "w", " "]);
  assert.deepEqual(keys(undefined), ["p", "w", " "]);
});

test("a group left with no entries disappears", () => {
  const tree: MenuNode = {
    key: "",
    name: "",
    children: [
      {
        key: "o",
        name: "org",
        children: [{ key: "l", name: "link", languages: ["org"] }],
      },
    ],
  };
  assert.deepEqual(filterMenu(tree, "python").children, []);
});

test("capture keys build a nested tree", () => {
  const tree = treeFromKeys(
    [
      { key: "t", description: "Todo" },
      { key: "w", description: "Work" },
      { key: "ww", description: "Work Todo" },
      { key: "wT", description: "Work tomorrow" },
    ],
    (item) => ({ command: item.key }),
  );
  const result = walk(tree, "wT");
  assert.equal(result.kind, "leaf");
  assert.equal(result.node.name, "Work tomorrow");
  assert.equal(result.node.command, "wT");
  assert.equal(walk(tree, "w").node.name, "Work");
  assert.equal(walk(tree, "t").kind, "leaf");
});
