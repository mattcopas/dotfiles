// Project discovery, following project.el's project-remember-projects-under.
// The filesystem is passed in so this stays testable without VS Code.

export interface ProjectRoot {
  path: string;
  recursive: boolean;
}

export interface DirectoryReader {
  /** Names of the sub-directories of a path, or an empty list if it isn't readable. */
  directories(path: string): Promise<string[]>;
  /** Whether a path contains a `.git` file or directory. */
  isRepository(path: string): Promise<boolean>;
}

const SKIP = new Set([
  "node_modules",
  "target",
  "build",
  "dist",
  "vendor",
  ".cache",
  "elpaca",
  "__pycache__",
  ".venv",
]);

export async function discoverProjects(
  roots: ProjectRoot[],
  reader: DirectoryReader,
  maxDepth = 4,
): Promise<string[]> {
  const found = new Set<string>();

  async function visit(path: string, recursive: boolean, depth: number) {
    if (await reader.isRepository(path)) {
      found.add(path);
      return;
    }
    if (depth >= maxDepth) {
      return;
    }
    const children = await reader.directories(path);
    await Promise.all(
      children
        .filter((name) => !name.startsWith(".") && !SKIP.has(name))
        .map(async (name) => {
          const child = `${path.replace(/\/$/, "")}/${name}`;
          if (recursive) {
            await visit(child, true, depth + 1);
          } else if (await reader.isRepository(child)) {
            found.add(child);
          }
        }),
    );
  }

  for (const root of roots) {
    await visit(root.path, root.recursive, 0);
  }
  return [...found];
}

/** Most recently used first, then alphabetical. */
export function sortProjects(projects: string[], recent: string[]): string[] {
  const rank = new Map(recent.map((path, index) => [path, index]));
  return [...projects].sort((a, b) => {
    const ra = rank.get(a);
    const rb = rank.get(b);
    if (ra !== undefined && rb !== undefined) {
      return ra - rb;
    }
    if (ra !== undefined) {
      return -1;
    }
    if (rb !== undefined) {
      return 1;
    }
    return a.localeCompare(b);
  });
}
