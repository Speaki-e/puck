import path from "node:path";

/** candidate가 root와 같거나 그 안에 있는지(경로 이탈 없이) 판별한다. 양쪽 다 이미 절대 경로여야 한다. */
export function isPathInside(root: string, candidate: string): boolean {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith(`..${path.sep}`) && relative !== ".." && !path.isAbsolute(relative));
}

/** candidate가 roots 중 하나라도 안에 있으면 true. */
export function isPathInsideAny(candidate: string, roots: readonly string[]): boolean {
  return roots.some((root) => isPathInside(root, candidate));
}
