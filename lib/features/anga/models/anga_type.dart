/// The type of anga (content) stored in Kaya.
enum AngaType {
  /// A bookmark stored as a .url file
  bookmark,

  /// A text blurb stored as a .md file (snippets, quotes, jotted text, etc.)
  blurb,

  /// Any other file type (images, PDFs, videos, etc.)
  file,
}

extension AngaTypeExtension on AngaType {
  String get displayName {
    switch (this) {
      case AngaType.bookmark:
        return 'Bookmark';
      case AngaType.blurb:
        return 'Blurb';
      case AngaType.file:
        return 'File';
    }
  }
}

/// Determines the AngaType from a filename.
AngaType angaTypeFromFilename(String filename) {
  final lower = filename.toLowerCase();

  if (lower.endsWith('.url')) {
    return AngaType.bookmark;
  }

  // Treat all markdown files as blurbs (includes -blurb.md, -note.md
  // legacy, -quote.md, etc.)
  if (lower.endsWith('.md')) {
    return AngaType.blurb;
  }

  return AngaType.file;
}
