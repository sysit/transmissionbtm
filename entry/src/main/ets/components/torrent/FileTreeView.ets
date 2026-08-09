// transmissionhm — FileTreeView (recursive torrent file browser)
//
// Renders a nested directory/file tree. Directories can be expanded/collapsed.
// Each file has a checkbox for download selection.
// Uses FileTreeModel.buildTree() to construct the tree from a flat TorrentFile[].

import { TorrentDir } from '../../models/TorrentDir';
import { TorrentFile } from '../../models/TorrentFile';
import { formatSize } from '../../utils/format';
import { Colors, Radius, Spacing, FontSize } from '../../utils/constants';

@Component
export struct FileTreeView {
  @Prop root: TorrentDir;
  @Link selectedFiles: boolean[];
  @State expandedDirs: Record<string, boolean> = {};

  aboutToAppear(): void {
    // Root directory starts expanded
    const rootKey = this.root.path || '/';
    this.expandedDirs[rootKey] = true;
  }

  build() {
    Column() {
      if (this.root.files.length > 0 || this.root.children.length > 0) {
        this.buildNode(this.root, 0);
      } else {
        Text('No files')
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT_TERTIARY)
          .padding(Spacing.LG);
      }
    }
    .width('100%');
  }

  @Builder
  buildNode(node: TorrentDir, depth: number) {
    Column() {
      // This directory's own files
      ForEach(node.files, (file: TorrentFile) => {
        this.buildFileItem(file, depth + 1);
      }, (file: TorrentFile) => `file-${file.index}`);

      // Child directories (recursive)
      ForEach(node.children, (child: TorrentDir) => {
        this.buildDirItem(child, depth);
      }, (child: TorrentDir) => `dir-${child.path}`);
    }
    .width('100%');
  }

  @Builder
  buildDirItem(dir: TorrentDir, depth: number) {
    Column() {
      // Directory header row
      Row() {
        // Indentation spacer
        if (depth > 0) {
          Row()
            .width(depth * 20)
            .height(1);
        }

        // Expand/collapse chevron
        Text(this.isDirExpanded(dir.path) ? '▾' : '▸')
          .fontSize(FontSize.CAPTION)
          .fontColor(Colors.TEXT_SECONDARY)
          .width(24)
          .textAlign(TextAlign.Center);

        // Directory icon
        Text('📁')
          .fontSize(FontSize.BODY)
          .margin({ right: Spacing.SM });

        // Directory name
        Text(dir.name || '/')
          .fontSize(FontSize.BODY)
          .fontColor(Colors.TEXT)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis });

        // Directory progress
        if (dir.totalSize > 0) {
          Text(`${Math.round(dir.percentComplete * 100)}%`)
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_TERTIARY)
            .fontFamily('JetBrains Mono')
            .margin({ right: Spacing.SM });
        }

        // Directory size
        Text(formatSize(dir.totalSize))
          .fontSize(FontSize.SMALL)
          .fontColor(Colors.TEXT_TERTIARY)
          .fontFamily('JetBrains Mono');
      }
      .width('100%')
      .height(44)
      .padding({ left: Spacing.SM, right: Spacing.SM })
      .borderRadius(Radius.SM)
      .onClick(() => { this.toggleDir(dir.path); });

      // Recursively render children when expanded
      if (this.isDirExpanded(dir.path)) {
        Column() {
          // Files in this directory
          ForEach(dir.files, (file: TorrentFile) => {
            this.buildFileItem(file, depth + 1);
          }, (file: TorrentFile) => `file-${dir.path}-${file.index}`);

          // Subdirectories
          ForEach(dir.children, (child: TorrentDir) => {
            this.buildDirItem(child, depth + 1);
          }, (child: TorrentDir) => `subdir-${child.path}`);
        }
        .width('100%');
      }
    }
    .width('100%');
  }

  @Builder
  buildFileItem(file: TorrentFile, depth: number) {
    Row() {
      // Indentation
      if (depth > 0) {
        Row()
          .width(depth * 20)
          .height(1);
      }

      // Checkbox
      Toggle({ type: ToggleType.Checkbox, isOn: this.isFileSelected(file.index) })
        .width(24)
        .height(24)
        .selectedColor(Colors.DOWNLOAD)
        .onChange((checked: boolean) => {
          this.toggleFile(file.index, checked);
        });

      // File icon
      Text(this.fileIcon(file.name))
        .fontSize(FontSize.BODY)
        .margin({ right: Spacing.SM });

      // File name
      Text(file.name.split('/').pop() ?? file.name)
        .fontSize(FontSize.CAPTION)
        .fontColor(Colors.TEXT)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis });

      // File progress
      if (file.size > 0) {
        Text(`${Math.round(file.percentComplete * 100)}%`)
          .fontSize(FontSize.SMALL)
          .fontColor(Colors.TEXT_TERTIARY)
          .fontFamily('JetBrains Mono')
          .margin({ right: Spacing.SM });
      }

      // File size
      Text(formatSize(file.size))
        .fontSize(FontSize.SMALL)
        .fontColor(Colors.TEXT_TERTIARY)
        .fontFamily('JetBrains Mono');
    }
    .width('100%')
    .height(40)
    .padding({ left: Spacing.SM, right: Spacing.SM })
    .borderRadius(Radius.SM);
  }

  // ═══════════════════════════════════════════════════════════════════
  // State helpers
  // ═══════════════════════════════════════════════════════════════════

  private isDirExpanded(path: string): boolean {
    const key = path || '/';
    return this.expandedDirs[key] ?? false;
  }

  private toggleDir(path: string): void {
    const key = path || '/';
    // Create new object to trigger @State update (immutability)
    const updated: Record<string, boolean> = {};
    const keys = Object.keys(this.expandedDirs);
    for (let i = 0; i < keys.length; i++) {
      updated[keys[i]] = this.expandedDirs[keys[i]];
    }
    updated[key] = !(this.expandedDirs[key] ?? false);
    this.expandedDirs = updated;
  }

  private isFileSelected(index: number): boolean {
    if (index >= 0 && index < this.selectedFiles.length) {
      return this.selectedFiles[index];
    }
    return true;
  }

  private toggleFile(index: number, checked: boolean): void {
    if (index >= 0 && index < this.selectedFiles.length) {
      // Immutable update of the array via @Link
      const updated: boolean[] = [];
      for (let i = 0; i < this.selectedFiles.length; i++) {
        updated.push(i === index ? checked : this.selectedFiles[i]);
      }
      this.selectedFiles = updated;
    }
  }

  private fileIcon(fileName: string): string {
    const ext = fileName.split('.').pop()?.toLowerCase() ?? '';
    switch (ext) {
      case 'mp4': case 'mkv': case 'avi': case 'mov': case 'webm':
        return '🎬';
      case 'mp3': case 'flac': case 'wav': case 'aac': case 'ogg':
        return '🎵';
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp':
        return '🖼';
      case 'pdf':
        return '📄';
      case 'zip': case 'rar': case '7z': case 'tar': case 'gz':
        return '📦';
      case 'iso':
        return '💿';
      case 'txt': case 'md': case 'log':
        return '📝';
      case 'exe': case 'app': case 'dmg':
        return '⚙';
      case 'srt': case 'sub': case 'vtt':
        return '💬';
      default:
        return '📄';
    }
  }
}
