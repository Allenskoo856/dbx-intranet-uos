/**
 * Compile-time/runtime marker for the UOS intranet package.
 *
 * The offline package still permits explicitly configured database, AI and
 * intranet service connections. It only disables DBX's own public update,
 * registry and background upload triggers.
 */
export const isUosOfflineBuild = import.meta.env.VITE_DBX_OFFLINE_MODE === "true";
