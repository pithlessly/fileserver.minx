const std = @import("std");

const log = @import("main.zig").log;

const Allocator = std.mem.Allocator;
const File = std.fs.File;

const FileType = enum {
    // display a code listing
    agda,
    c,
    cabal,
    cjam,
    cpp,
    elisp,
    gitignore,
    graphviz, // dot
    haskell,
    idris,
    java,
    json,
    koka,
    lean,
    lua,
    m4,
    makefile,
    nix,
    ocaml,
    okameron,
    perl,
    python,
    ruby,
    rust,
    scheme,
    shell,
    smalltalk,
    source_html,
    sql,
    standard_ml,
    tex,
    toml,
    typescript,
    typst,
    vim,
    xml,
    yaml,
    zig,

    // document formats
    djvu,
    epub,
    markdown,
    org,
    pdf,
    rst,
    text_utf8,

    // web technologies
    css,
    html,
    js,
    otf, // application/x-font-opentype
    wasm,
    woff2, // application/font-woff2
    woff, // application/font-woff

    // media formats
    gif,
    jpeg,
    m3u,
    m4a,
    mov,
    mp3,
    opus,
    png,
    svg,
    webm,
    webp,

    pub fn highlightPandocLanguage(self: FileType) ?[]const u8 {
        return switch (self) {
            .agda => "agda",
            .cabal => "cabal", // not supported by pandoc
            .c => "c",
            .cjam => "cjam", // not supported by pandoc
            .cpp => "cpp",
            .elisp => "commonlisp", // elisp is not supported by pandoc
            .gitignore => "gitignore", // not supported bv pandoc
            .graphviz => "dot",
            .haskell => "haskell",
            .idris => "idris",
            .java => "java",
            .json => "json",
            .koka => "koka", // not supported by pandoc
            .lean => "lean", // not supported by pandoc
            .lua => "lua",
            .m4 => "m4",
            .makefile => "makefile",
            .nix => "nix",
            .ocaml => "ocaml",
            .okameron => "okameron", // not supported by pandoc
            .perl => "perl",
            .python => "python",

            .ruby => "ruby",
            .rust => "rust",
            .scheme => "scheme",
            .shell => "bash",
            .smalltalk => "smalltalk", // not supported by pandoc
            .source_html => "html",
            .sql => "sql",
            .standard_ml => "sml",
            .tex => "tex",
            .toml => "toml",
            .typescript => "typescript",
            .typst => "typst",
            .vim => "vim", // not supported by pandoc
            .xml => "xml",
            .yaml => "yaml",
            .zig => "zig",

            else => null,
        };
    }

    pub fn pandocDocumentFormat(self: FileType) ?[]const u8 {
        return switch (self) {
            .markdown => "markdown",
            .rst => "rst",
            .org => "org",
            else => null,
        };
    }
};

const FileTypeAssoc = struct {
    str: []const u8,
    ty: FileType,
    fn assoc(ty: FileType, str: []const u8) FileTypeAssoc {
        return .{ .str = str, .ty = ty };
    }
};

const suffixes = [_]FileTypeAssoc{
    .assoc(.agda, ".agda"),
    .assoc(.cabal, ".cabal"),
    .assoc(.c, ".c"),
    .assoc(.cjam, ".cjam"),
    .assoc(.cpp, ".cpp"),
    .assoc(.cpp, ".h"),
    .assoc(.elisp, ".el"),
    .assoc(.gitignore, ".gitignore"),
    .assoc(.graphviz, ".dot"),
    .assoc(.haskell, ".hs"),
    .assoc(.idris, ".idr"),
    .assoc(.idris, ".idris"),
    .assoc(.java, ".java"),
    .assoc(.json, ".json"),
    .assoc(.koka, ".koka"),
    .assoc(.lean, ".lean"),
    .assoc(.lua, ".lua"),
    .assoc(.m4, ".m4"),
    .assoc(.makefile, ".Makefile"),
    .assoc(.makefile, ".mk"),
    .assoc(.nix, ".nix"),
    .assoc(.ocaml, ".ml"),
    .assoc(.ocaml, ".mini-ml"),
    .assoc(.ocaml, ".mli"),
    .assoc(.ocaml, ".ocamlinit"),
    .assoc(.okameron, ".okm"),
    .assoc(.perl, ".pl"),
    .assoc(.python, ".py"),
    .assoc(.ruby, ".rb"),
    .assoc(.rust, ".rs"),
    .assoc(.scheme, ".scm"),
    .assoc(.scheme, ".sls"),
    .assoc(.scheme, ".sps"),
    .assoc(.shell, ".bash"),
    .assoc(.shell, ".sh"),
    .assoc(.shell, ".zsh"),
    .assoc(.smalltalk, ".st"),
    .assoc(.source_html, ".eta"),
    .assoc(.sql, ".sql"),
    .assoc(.standard_ml, ".fun"),
    .assoc(.standard_ml, ".sig"),
    .assoc(.standard_ml, ".sml"),
    .assoc(.tex, ".tex"),
    .assoc(.toml, ".toml"),
    .assoc(.typescript, ".ts"),
    .assoc(.typst, ".typ"),
    .assoc(.typst, ".Typ"),
    .assoc(.vim, ".vim"),
    .assoc(.vim, ".vimrc"),
    .assoc(.xml, ".xml"),
    .assoc(.yaml, ".yaml"),
    .assoc(.yaml, ".yml"),
    .assoc(.zig, ".zig"),
    .assoc(.zig, ".zon"),

    .assoc(.djvu, ".djvu"),
    .assoc(.epub, ".epub"),
    .assoc(.markdown, ".md"),
    .assoc(.org, ".org"),
    .assoc(.pdf, ".pdf"),
    .assoc(.rst, ".rst"),
    .assoc(.text_utf8, ".txt"),

    .assoc(.css, ".css"),
    .assoc(.html, ".html"),
    .assoc(.js, ".js"),
    .assoc(.js, ".mjs"),
    .assoc(.wasm, ".wasm"),
    .assoc(.woff2, ".woff2"),
    .assoc(.woff, ".woff"),

    .assoc(.gif, ".gif"),
    .assoc(.jpeg, ".jpeg"),
    .assoc(.jpeg, ".jpg"),
    .assoc(.m3u, ".m3u"),
    .assoc(.m4a, ".m4a"),
    .assoc(.mov, ".mov"),
    .assoc(.mp3, ".mp3"),
    .assoc(.opus, ".opus"),
    .assoc(.png, ".png"),
    .assoc(.png, ".PNG"),
    .assoc(.svg, ".svg"),
    .assoc(.webm, ".webm"),
    .assoc(.webp, ".webp"),
};

const fixed_filenames = [_]FileTypeAssoc{
    .assoc(.makefile, "Makefile"),
    .assoc(.makefile, "GNUmakefile"),
    .assoc(.gitignore, ".gitignore"),
    .assoc(.gitignore, "gitignore_global"),
    .assoc(.gitignore, ".build-gitignore"),
};

const Trie = struct {
    as_fixed: ?FileType = null,
    as_suffix: ?FileType = null,
    children: ChildMap = .{},

    const ChildMap = std.AutoHashMapUnmanaged(u8, *Trie);
};

// TODO: better compression?
pub const NameMap = struct {
    root: Trie,

    const Self = NameMap;

    fn getNode(self: *Self, ally: Allocator, name: []const u8) !*Trie {
        var i: usize = name.len;
        var trie_node = &self.root;
        while (i > 0) {
            i -= 1;
            const char = name[i];
            const result = try trie_node.children.getOrPut(ally, char);
            if (result.found_existing) {
                trie_node = result.value_ptr.*;
            } else {
                trie_node = try ally.create(Trie);
                trie_node.* = .{};
                result.value_ptr.* = trie_node;
            }
        }
        return trie_node;
    }

    fn addSuffix(self: *Self, ally: Allocator, name: []const u8, ty: FileType) !void {
        const node = try self.getNode(ally, name);
        if (node.as_suffix != null) {
            log.err("can't add this suffix to filetype map: {s}", .{name});
            return error.FileTypeMap;
        }
        node.as_suffix = ty;
    }

    fn addFixedFilename(self: *Self, ally: Allocator, name: []const u8, ty: FileType) !void {
        const node = try self.getNode(ally, name);
        if (node.as_fixed != null) {
            log.err("can't add this fixed filename to filetype map: {s}", .{name});
            return error.FileTypeMap;
        }
        node.as_fixed = ty;
    }

    pub fn init(gpa: Allocator) !Self {
        var self = Self{ .root = .{} };
        for (suffixes) |assoc| {
            try self.addSuffix(gpa, assoc.str, assoc.ty);
        }
        for (fixed_filenames) |assoc| {
            try self.addFixedFilename(gpa, assoc.str, assoc.ty);
        }
        return self;
    }

    pub fn fileTypeFor(self: Self, path: []const u8) ?FileType {
        const basename = std.fs.path.basename(path);
        var i = basename.len;
        var trie_node = &self.root;
        while (true) {
            if (i == 0) {
                break;
            }
            if (trie_node.as_suffix) |ft|
                return ft;
            i -= 1;
            const char = basename[i];
            if (char == '/') break;
            trie_node = trie_node.children.get(char) orelse return null;
        }
        return trie_node.as_fixed;
    }
};

fn isUtf8ContinuationByte(b: u8) bool {
    return b >> 6 == 0b10;
}

pub fn startsWithUtf8(f: File) !bool {
    var buf: [128]u8 = undefined;
    const n_read = try f.readAll(&buf);
    var validate_len = n_read;
    if (n_read == buf.len) {
        // skip incomplete characters at the end: omit up to 3 bytes
        var i: usize = 0;
        while (i < 3 and isUtf8ContinuationByte(buf[validate_len - 1])) {
            i += 1;
            validate_len -= 1;
        }
        if (i > 0) {
            validate_len -= 1;
            i += 1;
            const leading_byte = buf[validate_len];
            const last_character_len = std.unicode.utf8ByteSequenceLength(leading_byte) catch
                return false;
            if (!(last_character_len >= i))
                return false;
        }
    }
    return std.unicode.wtf8ValidateSlice(buf[0..validate_len]);
}
