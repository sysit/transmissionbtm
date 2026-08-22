// transmissionbtm — FileTreeModel
//
// Builds a recursive TorrentDir tree from a flat list of TorrentFile entries.
// Handles arbitrarily nested directory structures.

import { TorrentFile } from './TorrentFile';
import { TorrentDir } from './TorrentDir';

export class FileTreeModel {
  /**
   * Build a directory tree from a flat file list.
   * Files whose names contain '/' are nested into intermediate directories;
   * their `name` is normalized to the basename, `path` keeps the full
   * relative path. Files at the root level are placed directly in root.files.
   *
   * @param files Flat list of TorrentFile entries from listFromNative()
   * @returns A TorrentDir representing the root of the file tree.
   *          The root's name is empty (''), path is '', depth is 0.
   */
  static buildTree(files: TorrentFile[]): TorrentDir {
    const root = new TorrentDir();
    root.name = '';
    root.path = '';
    root.depth = 0;
    root.parent = null;

    // Map path → created directory node for reuse
    const dirMap = new Map<string, TorrentDir>();
    dirMap.set('', root);

    /**
     * Ensure a directory exists at the given path, creating intermediate
     * directories as needed.
     */
    const ensureDir = (fullPath: string, parts: string[],
                       endIdx: number): TorrentDir => {
      const dirPath = parts.slice(0, endIdx + 1).join('/');
      const existing = dirMap.get(dirPath);
      if (existing) {
        return existing;
      }

      const dir = new TorrentDir();
      dir.name = parts[endIdx];
      dir.path = dirPath;
      dir.depth = endIdx + 1;

      dirMap.set(dirPath, dir);

      // Attach to parent
      if (endIdx === 0) {
        dir.parent = root;
        root.children.push(dir);
      } else {
        const parent = ensureDir(fullPath, parts, endIdx - 1);
        dir.parent = parent;
        parent.children.push(dir);
      }

      return dir;
    };

    for (const file of files) {
      // Split on '/' — handles both "dir/file.txt" and "dir/sub/file.txt"
      const parts = file.name.split('/');

      if (parts.length > 1) {
        // File lives under one or more directories
        const parentDir = ensureDir(file.name, parts, parts.length - 2);
        file.path = file.name; // full relative path (search key for findFile)
        file.name = parts[parts.length - 1]; // basename for display
        parentDir.files.push(file);
      } else {
        // File at root level
        file.path = file.name;
        root.files.push(file);
      }
    }

    return root;
  }

  /**
   * Flatten a TorrentDir tree back into a depth-ordered array of nodes.
   * Directories appear before their children. Useful for rendering
   * indented file lists.
   *
   * @param root The root directory to flatten
   * @returns Array of all TorrentDir nodes in pre-order (directories first,
   *          then each directory's files are implicitly between its children)
   */
  static flattenToList(root: TorrentDir): TorrentDir[] {
    const result: TorrentDir[] = [];
    const walk = (dir: TorrentDir): void => {
      result.push(dir);
      for (const child of dir.children) {
        walk(child);
      }
    };
    walk(root);
    return result;
  }

  /**
   * Count all distinct directories in the tree (including root).
   */
  static countDirectories(root: TorrentDir): number {
    let count = 1; // root
    for (const child of root.children) {
      count += FileTreeModel.countDirectories(child);
    }
    return count;
  }

  /**
   * Find a directory node by its full path within the tree.
   * Returns null if not found.
   */
  static findDir(root: TorrentDir, targetPath: string): TorrentDir | null {
    if (root.path === targetPath) {
      return root;
    }
    for (const child of root.children) {
      const found = FileTreeModel.findDir(child, targetPath);
      if (found) {
        return found;
      }
    }
    return null;
  }

  /**
   * Find a file by its full path within the tree.
   * Returns null if not found.
   */
  static findFile(root: TorrentDir, targetPath: string): TorrentFile | null {
    // Check files in this directory
    for (const f of root.files) {
      if (f.path === targetPath) {
        return f;
      }
    }
    // Recursively search subdirectories
    for (const child of root.children) {
      const found = FileTreeModel.findFile(child, targetPath);
      if (found) {
        return found;
      }
    }
    return null;
  }
}
