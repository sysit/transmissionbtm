// transmissionhm — FileTreeModel.buildTree() and TorrentDir tests
//
// Pure logic tests for the recursive file tree builder.
// Cross-referenced against transmissionbtc PathItem.split() and
// MiscTest.testPathItem() tree-building patterns.

import { describe, it, expect } from '@ohos/hypium';
import { TorrentFile } from '../../../main/ets/models/TorrentFile';
import { TorrentDir } from '../../../main/ets/models/TorrentDir';
import { FileTreeModel } from '../../../main/ets/models/FileTreeModel';

/**
 * Helper: create a TorrentFile with given fields.
 * All fields except the four specified receive sensible defaults.
 */
function makeFile(
  index: number,
  name: string,
  size: number,
  bytesCompleted: number,
): TorrentFile {
  const f: TorrentFile = new TorrentFile();
  f.index = index;
  f.name = name;
  f.size = size;
  f.bytesCompleted = bytesCompleted;
  f.wanted = true;
  f.priority = 0;
  return f;
}

export default function fileTreeModelTest(): void {
  describe('FileTreeModel.buildTree', () => {
    it('flat_files_no_directories', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'a.txt', 100, 50),
        makeFile(1, 'b.txt', 200, 200),
        makeFile(2, 'c.txt', 300, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      // Root directory has empty name
      expect(tree.name).assertEqual('');
      expect(tree.path).assertEqual('');
      expect(tree.depth).assertEqual(0);
      // All three files go directly under root
      expect(tree.files.length).assertEqual(3);
      // No subdirectories
      expect(tree.children.length).assertEqual(0);
    });

    it('single_directory_with_files', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'docs/readme.txt', 100, 100),
        makeFile(1, 'docs/guide.pdf', 500, 250),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      // Root has no files directly
      expect(tree.files.length).assertEqual(0);
      // One subdirectory: docs/
      expect(tree.children.length).assertEqual(1);
      const docsDir: TorrentDir = tree.children[0];
      expect(docsDir.name).assertEqual('docs');
      expect(docsDir.path).assertEqual('docs');
      expect(docsDir.depth).assertEqual(1);
      expect(docsDir.parent).assertEqual(tree);
      // docs/ contains both files
      expect(docsDir.files.length).assertEqual(2);
    });

    it('nested_directory_hierarchy', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'src/main/index.ets', 1000, 500),
        makeFile(1, 'src/test/List.test.ets', 2000, 0),
        makeFile(2, 'README.md', 50, 50),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      // Root has README.md and src/
      expect(tree.files.length).assertEqual(1);
      expect(tree.files[0].name).assertEqual('README.md');
      expect(tree.children.length).assertEqual(1);

      const srcDir: TorrentDir = tree.children[0];
      expect(srcDir.name).assertEqual('src');
      expect(srcDir.path).assertEqual('src');
      // src/ has two subdirectories: main/ and test/
      expect(srcDir.children.length).assertEqual(2);
      expect(srcDir.files.length).assertEqual(0);

      // Verify child names (order matches insertion)
      const childNames: string[] = [];
      for (const child of srcDir.children) {
        childNames.push(child.name);
      }
      // main/ was inserted first, test/ second
      expect(childNames[0]).assertEqual('main');
      expect(childNames[1]).assertEqual('test');

      // main/ contains index.ets
      const mainDir: TorrentDir = srcDir.children[0];
      expect(mainDir.files.length).assertEqual(1);
      expect(mainDir.files[0].name).assertEqual('index.ets');
    });

    it('deeply_nested_path_of_five_levels', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'a/b/c/d/e/deep.txt', 100, 100),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      // Walk down five levels
      let current: TorrentDir = tree;
      const parts: string[] = ['a', 'b', 'c', 'd', 'e'];
      for (let i = 0; i < parts.length; i++) {
        expect(current.children.length).assertEqual(1);
        current = current.children[0];
        expect(current.name).assertEqual(parts[i]);
      }
      // Leaf directory 'e' contains deep.txt
      expect(current.files.length).assertEqual(1);
      expect(current.files[0].name).assertEqual('deep.txt');
    });

    it('mixed_root_and_nested_files', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'top.txt', 10, 0),
        makeFile(1, 'sub/mid.txt', 20, 10),
        makeFile(2, 'sub/deep/bottom.txt', 30, 30),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      // Root has top.txt
      expect(tree.files.length).assertEqual(1);
      expect(tree.files[0].name).assertEqual('top.txt');
      // Root has sub/
      expect(tree.children.length).assertEqual(1);
      const subDir: TorrentDir = tree.children[0];
      expect(subDir.name).assertEqual('sub');
      // sub/ has mid.txt and deep/
      expect(subDir.files.length).assertEqual(1);
      expect(subDir.files[0].name).assertEqual('mid.txt');
      expect(subDir.children.length).assertEqual(1);
      // deep/ has bottom.txt
      const deepDir: TorrentDir = subDir.children[0];
      expect(deepDir.name).assertEqual('deep');
      expect(deepDir.files.length).assertEqual(1);
      expect(deepDir.files[0].name).assertEqual('bottom.txt');
    });

    it('empty_files_returns_empty_root', 0, (): void => {
      const tree: TorrentDir = FileTreeModel.buildTree([]);
      expect(tree.files.length).assertEqual(0);
      expect(tree.children.length).assertEqual(0);
      expect(tree.totalSize).assertEqual(0);
      expect(tree.percentComplete).assertEqual(0);
    });
  });

  describe('TorrentDir aggregated getters', () => {
    it('totalSize_aggregates_all_files_recursively', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'videos/a.mp4', 1000, 1000),
        makeFile(1, 'videos/b.mp4', 2000, 500),
        makeFile(2, 'subtitles/en.srt', 100, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      // 1000 + 2000 + 100 = 3100
      expect(tree.totalSize).assertEqual(3100);

      // videos/ directory aggregates a.mp4 + b.mp4
      const videosDir: TorrentDir = tree.children[0];
      expect(videosDir.totalSize).assertEqual(3000);

      // subtitles/ directory
      const subsDir: TorrentDir = tree.children[1];
      expect(subsDir.totalSize).assertEqual(100);
    });

    it('totalBytesCompleted_aggregates_recursively', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'a.txt', 100, 100),
        makeFile(1, 'sub/b.txt', 200, 50),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      // 100 + 50 = 150
      expect(tree.totalBytesCompleted).assertEqual(150);
    });

    it('percentComplete_calculated_from_bytes_and_size', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'file.bin', 1000, 750),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      // 750 / 1000 = 0.75
      expect(tree.percentComplete).assertEqual(0.75);
    });

    it('percentComplete_zero_when_totalSize_zero', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'empty.bin', 0, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      // Guard against division by zero — should return 0
      expect(tree.percentComplete).assertEqual(0);
    });

    it('fileCount_counts_all_files_recursively', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'a.txt', 10, 0),
        makeFile(1, 'sub/b.txt', 20, 0),
        makeFile(2, 'sub/c.txt', 30, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      expect(tree.fileCount).assertEqual(3);

      const subDir: TorrentDir = tree.children[0];
      expect(subDir.fileCount).assertEqual(2);
    });

    it('dirCount_counts_all_subdirectories', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'a/b/c/file.txt', 10, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      // Root has 3 subdirectories: a, b, c — dirCount excludes root itself,
      // mirroring fileCount which excludes any pseudo-root file.
      expect(tree.dirCount).assertEqual(3);
    });
  });

  describe('FileTreeModel.flattenToList', () => {
    it('returns_only_directory_nodes_in_preorder', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'a.txt', 100, 100),
        makeFile(1, 'sub/b.txt', 200, 200),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      const flat: TorrentDir[] = FileTreeModel.flattenToList(tree);
      // flattenToList returns TorrentDir[] — directories only, not files.
      // Tree: root (depth 0) + sub/ (depth 1) = 2 directory nodes
      expect(flat.length).assertEqual(2);
      expect(flat[0].name).assertEqual('');    // root
      expect(flat[1].name).assertEqual('sub'); // subdirectory
    });

    it('deeply_nested_directories_flatten_correctly', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'x/y/z/file.txt', 10, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      const flat: TorrentDir[] = FileTreeModel.flattenToList(tree);
      // root + x + x/y + x/y/z = 4 directories
      expect(flat.length).assertEqual(4);
      expect(flat[0].name).assertEqual('');
      expect(flat[1].name).assertEqual('x');
      expect(flat[2].name).assertEqual('y');
      expect(flat[3].name).assertEqual('z');
    });

    it('flat_root_only_returns_single_element', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'only.txt', 100, 100),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      const flat: TorrentDir[] = FileTreeModel.flattenToList(tree);
      expect(flat.length).assertEqual(1);
      expect(flat[0].name).assertEqual('');
    });
  });

  describe('FileTreeModel.countDirectories', () => {
    it('counts_root_plus_all_descendants', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'a/b/file.txt', 10, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      const count: number = FileTreeModel.countDirectories(tree);
      // root + a/ + a/b/ = 3 directories
      expect(count).assertEqual(3);
    });

    it('returns_one_for_flat_tree', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'f1.txt', 10, 0),
        makeFile(1, 'f2.txt', 20, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      const count: number = FileTreeModel.countDirectories(tree);
      expect(count).assertEqual(1); // root only
    });
  });

  describe('FileTreeModel.findDir', () => {
    it('finds_root_by_empty_path', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'sub/file.txt', 10, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      const found: TorrentDir | null = FileTreeModel.findDir(tree, '');
      expect(found).assertEqual(tree);
    });

    it('finds_nested_directory_by_path', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'a/b/file.txt', 10, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      const found: TorrentDir | null = FileTreeModel.findDir(tree, 'a/b');
      expect(found === null).assertFalse();
      if (found) {
        expect(found.name).assertEqual('b');
        expect(found.path).assertEqual('a/b');
      }
    });

    it('returns_null_for_nonexistent_path', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'real/file.txt', 10, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      const found: TorrentDir | null = FileTreeModel.findDir(tree, 'nonexistent');
      expect(found === null).assertTrue();
    });
  });

  describe('FileTreeModel.findFile', () => {
    it('finds_file_in_root', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'readme.txt', 100, 100),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      const found: TorrentFile | null = FileTreeModel.findFile(tree, 'readme.txt');
      expect(found === null).assertFalse();
      if (found) {
        expect(found.name).assertEqual('readme.txt');
        expect(found.size).assertEqual(100);
      }
    });

    it('finds_file_in_subdirectory', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'sub/deep/hidden.txt', 200, 200),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      const found: TorrentFile | null = FileTreeModel.findFile(tree, 'sub/deep/hidden.txt');
      expect(found === null).assertFalse();
      if (found) {
        expect(found.name).assertEqual('hidden.txt');
        expect(found.size).assertEqual(200);
      }
    });

    it('returns_null_for_nonexistent_file', 0, (): void => {
      const files: TorrentFile[] = [
        makeFile(0, 'real.txt', 10, 0),
      ];
      const tree: TorrentDir = FileTreeModel.buildTree(files);
      const found: TorrentFile | null = FileTreeModel.findFile(tree, 'ghost.txt');
      expect(found === null).assertTrue();
    });
  });

  describe('FileTreeModel buildTree parity with upstream PathItem', () => {
    // transmissionbtc MiscTest.testPathItem() builds a tree from paths
    // like "/a/b/c/d", "a/b/c/e", "c", etc. and verifies sorted output.
    // This test mirrors that structure with our TorrentFile model.

    it('complex_mixed_tree_matches_upstream_pattern', 0, (): void => {
      const paths: string[] = [
        '/a/b/c/d',
        'a/b/c/e',
        'c',
        'a/c',
        'a/f',
        'e',
        'b/c',
        'b/d',
      ];
      const files: TorrentFile[] = [];
      for (let i = 0; i < paths.length; i++) {
        // Strip leading slash for consistency (TorrentFile names are relative)
        let name: string = paths[i];
        if (name.startsWith('/')) {
          name = name.substring(1);
        }
        files.push(makeFile(i, name, 100, 50));
      }
      const tree: TorrentDir = FileTreeModel.buildTree(files);

      // Verify all 8 files are reachable
      expect(tree.fileCount).assertEqual(8);

      // Root should have: c, e (direct files), and a/, b/ (directories)
      // Path "c" → root file
      // Path "e" → root file
      // Path "a/b/c/d" → creates a/, a/b/, a/b/c/ dirs + file d
      // Path "a/b/c/e" → file e under a/b/c/
      // Path "a/c" → file under a/ (not a directory named c under a)
      // Path "a/f" → file under a/
      // Path "b/c" → creates b/ dir + file c under b/
      // Path "b/d" → file under b/

      // Root-level files: 'c', 'e'
      expect(tree.files.length).assertEqual(2);
      // Root-level dirs: 'a', 'b'
      expect(tree.children.length).assertEqual(2);

      // a/ directory: files 'c', 'f' + dir 'b'
      const dirA: TorrentDir = tree.children[0];
      expect(dirA.name).assertEqual('a');
      expect(dirA.files.length).assertEqual(2); // c, f
      expect(dirA.children.length).assertEqual(1); // b/

      // b/ (root-level) directory: files 'c', 'd'
      const dirB: TorrentDir = tree.children[1];
      expect(dirB.name).assertEqual('b');
      expect(dirB.files.length).assertEqual(2); // c, d
      expect(dirB.children.length).assertEqual(0);
    });
  });
}
