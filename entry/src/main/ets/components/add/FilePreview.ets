// transmissionbtm — FilePreview (read-only preview of a picked .torrent file)
//
// Extracted from AddTorrentPage.buildFilePreview() so the page stays focused on
// the add flow. Presents the path's basename + full path; purely presentational.

import { Colors, Radius, Spacing, FontSize } from '../../utils/constants';

@Component
export struct FilePreview {
  @Prop path: string = '';

  build() {
    Column() {
      Row() {
        Text('📄')
          .fontSize(20)
          .margin({ right: Spacing.MD });

        Column() {
          Text(this.baseName(this.path))
            .fontSize(FontSize.CAPTION)
            .fontColor(Colors.TEXT)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });

          Text(this.path)
            .fontSize(FontSize.SMALL)
            .fontColor(Colors.TEXT_TERTIARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis });
        }
        .layoutWeight(1);
      }
      .width('100%');
    }
    .width('100%')
    .padding(Spacing.MD)
    .borderRadius(Radius.MD)
    .backgroundColor(Colors.SURFACE)
    .margin({ bottom: Spacing.LG });
  }

  private baseName(path: string): string {
    const parts = path.split('/');
    return parts.length > 0 ? parts[parts.length - 1] : path;
  }
}
