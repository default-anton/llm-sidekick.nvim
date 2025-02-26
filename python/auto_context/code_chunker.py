import re
import logging
import traceback
from dataclasses import dataclass

from tree_sitter import Node, Tree
from tree_sitter_language_pack import get_parser

logger = logging.getLogger(__name__)

@dataclass
class Span:
    # Represents a slice of a string
    start: int = 0
    end: int = 0

    def __post_init__(self):
        # If end is None, set it to start
        if self.end is None:
            self.end = self.start

    def extract(self, s: str) -> str:
        # Grab the corresponding substring of string s by bytes
        return s[self.start : self.end]

    def extract_lines(self, s: str) -> str:
        # Grab the corresponding substring of string s by lines
        return "\n".join(s.splitlines()[self.start : self.end])

    def __add__(self, other: 'Span | int') -> 'Span':
        # e.g. Span(1, 2) + Span(2, 4) = Span(1, 4) (concatenation)
        # There are no safety checks: Span(a, b) + Span(c, d) = Span(a, d)
        # and there are no requirements for b = c.
        if isinstance(other, int):
            return Span(self.start + other, self.end + other)
        elif isinstance(other, Span):
            return Span(self.start, other.end)

    def __len__(self) -> int:
        # i.e. Span(a, b) = b - a
        return self.end - self.start

def non_whitespace_len(s: str) -> int:  # new len function
    return len(re.sub(r"\s", "", s))

def get_line_number(index: int, source_code: str) -> int:
    total_chars = 0
    for line_number, line in enumerate(source_code.splitlines(keepends=True), start=1):
        total_chars += len(line)
        if total_chars > index:
            return line_number - 1

    return line_number

@dataclass
class CodeSnippet:
    """Represents a code snippet with its content and location information."""
    content: str
    start: int
    end: int
    file_path: str

def chunk_tree(
    tree: Tree,
    source_code: str,
    max_chars=1200,
    min_chars=200,  # Minimum characters for a chunk to be considered complete
    coalesce=150,   # Chunks less than this get coalesced
) -> list[Span]:

    # 1. Recursively form chunks based on the last post (https://docs.sweep.dev/blogs/chunking-2m-files)
    def chunk_node(node: Node) -> list[Span]:
        chunks: list[Span] = []
        current_chunk: Span = Span(node.start_byte, node.start_byte)
        node_children = node.children
        for child in node_children:
            # If this child is already too big, chunk it separately
            if child.end_byte - child.start_byte > max_chars:
                # Only add the current chunk if it has content
                if current_chunk.end > current_chunk.start:
                    chunks.append(current_chunk)
                current_chunk = Span(child.end_byte, child.end_byte)
                chunks.extend(chunk_node(child))
            # If adding this child would make the chunk too big, start a new chunk
            elif child.end_byte - child.start_byte + len(current_chunk) > max_chars:
                chunks.append(current_chunk)
                current_chunk = Span(child.start_byte, child.end_byte)
            # Otherwise, add this child to the current chunk
            else:
                current_chunk += Span(child.start_byte, child.end_byte)

        # Add the final chunk if it has content
        if current_chunk.end > current_chunk.start:
            chunks.append(current_chunk)
        return chunks

    chunks = chunk_node(tree.root_node)

    # 2. Filling in the gaps
    if len(chunks) == 0:
        return []
    if len(chunks) < 2:
        end = get_line_number(chunks[0].end, source_code)
        return [Span(0, end)]

    # Fill in gaps between chunks
    for i in range(len(chunks) - 1):
        chunks[i].end = chunks[i + 1].start
    chunks[-1].end = tree.root_node.end_byte

    # 3. Combining small chunks with bigger ones - improved coalescing logic
    new_chunks = []
    current_chunk = Span(0, 0)

    for i, chunk in enumerate(chunks):
        current_chunk += chunk
        chunk_content = current_chunk.extract(source_code)
        non_ws_len = non_whitespace_len(chunk_content)

        # Decide whether to keep accumulating or create a new chunk
        # We create a new chunk if:
        # 1. The current chunk is large enough (exceeds coalesce threshold)
        # 2. AND contains at least one newline (to avoid breaking in the middle of a line)
        # 3. AND either meets the minimum size or we're at the last chunk
        if (non_ws_len > coalesce and
            "\n" in chunk_content and
            (non_ws_len >= min_chars or i == len(chunks) - 1)):
            new_chunks.append(current_chunk)
            current_chunk = Span(chunk.end, chunk.end)

    # Add any remaining content
    if current_chunk.end > current_chunk.start:
        new_chunks.append(current_chunk)

    # 4. Changing to line numbers
    line_chunks = [
        Span(
            get_line_number(chunk.start, source_code),
            get_line_number(chunk.end, source_code),
        )
        for chunk in new_chunks
    ]

    # 5. Eliminating empty chunks
    line_chunks = [chunk for chunk in line_chunks if len(chunk) > 0]

    # 6. Coalescing very small chunks with nearby chunks
    # First, coalesce with previous chunk if possible
    i = 1
    while i < len(line_chunks):
        if len(line_chunks[i]) < min(coalesce // 10, 15):  # Very small chunks
            line_chunks[i-1] += line_chunks[i]
            line_chunks.pop(i)
        else:
            i += 1

    # Finally, coalesce the last chunk if it's too small
    if len(line_chunks) > 1 and len(line_chunks[-1]) < min(coalesce // 5, 30):
        line_chunks[-2] += line_chunks[-1]
        line_chunks.pop()

    return line_chunks

def naive_chunker(code: str, line_count: int = 40, overlap: int = 5):
    """Fallback chunker that uses line-based chunking with overlap."""
    if overlap >= line_count:
        raise ValueError("Overlap should be smaller than line_count.")
    lines = code.split("\n")
    total_lines = len(lines)
    chunks = []

    start = 0
    while start < total_lines:
        end = min(start + line_count, total_lines)
        chunk = "\n".join(lines[start:end])
        chunks.append(chunk)
        start += line_count - overlap

    return chunks

EXTENSION_TO_LANGUAGE = {
    "py": "python",
    "js": "tsx",
    "jsx": "tsx",
    "ts": "tsx",
    "tsx": "tsx",
    "mjs": "tsx",
    "vue": "vue",
    "rs": "rust",
    "go": "go",
    "java": "java",
    "cpp": "cpp",
    "c": "c",
    "h": "c",
    "hpp": "cpp",
    "cs": "csharp",
    "rb": "ruby",
    "php": "php",
    "scala": "scala",
    "kt": "kotlin",
    "lua": "lua",
    "erb": "html",
    "haml": "html",
    "slim": "html",
    "builder": "html",
    "sh": "bash",
    "zsh": "bash",
    "bash": "bash",
    "asm": "asm",
    "s": "asm",
    "astro": "astro",
    "clj": "clojure",
    "cljs": "clojure",
    "cmake": "cmake",
    "css": "css",
    "scss": "scss",
    "csv": "csv",
    "tsv": "tsv",
    "psv": "psv",
    "dart": "dart",
    "ex": "elixir",
    "exs": "elixir",
    "erl": "erlang",
    "hrl": "erlang",
    "hs": "haskell",
    "html": "html",
    "json": "json",
    "tex": "latex",
    "md": "markdown",
    "mdx": "markdown",
    "mk": "make",
    "ddl": "sql",
    "sql": "sql",
    "swift": "swift",
    "vim": "vim",
    "xsd": "xml",
    "xsl": "xml",
    "xml": "xml",
    "yaml": "yaml",
    "yml": "yaml",
    "as": "actionscript",
    "adb": "ada",
    "ads": "ada",
    "agda": "agda",
    "ino": "arduino",
    "bc": "beancount",
    "bib": "bibtex",
    "bicep": "bicep",
    "bb": "bitbake",
    "cairo": "cairo",
    "capnp": "capnp",
    "chatito": "chatito",
    "clar": "clarity",
    "cl": "commonlisp",
    "lisp": "commonlisp",
    "cpon": "cpon",
    "cu": "cuda",
    "cuh": "cuda",
    "d": "d",
    "dockerfile": "dockerfile",
    "dox": "doxygen",
    "dtd": "dtd",
    "el": "elisp",
    "elm": "elm",
    "fnl": "fennel",
    "fir": "firrtl",
    "fish": "fish",
    "f": "fortran",
    "f90": "fortran",
    "func": "func",
    "gd": "gdscript",
    "gitattributes": "gitattributes",
    "gitcommit": "gitcommit",
    "gitignore": "gitignore",
    "gleam": "gleam",
    "glsl": "glsl",
    "gn": "gn",
    "mod": "gomod",
    "sum": "gosum",
    "groovy": "groovy",
    "launch": "gstlaunch",
    "hack": "hack",
    "ha": "hare",
    "hx": "haxe",
    "hcl": "hcl",
    "tf": "terraform",
    "heex": "heex",
    "hlsl": "hlsl",
    "hypr": "hyprlang",
    "ispc": "ispc",
    "janet": "janet",
    "jsdoc": "jsdoc",
    "jsonnet": "jsonnet",
    "jl": "julia",
    "kconfig": "kconfig",
    "kdl": "kdl",
    "ld": "linkerscript",
    "ll": "llvm",
    "luadoc": "luadoc",
    "luap": "luap",
    "luau": "luau",
    "m": "matlab",
    "mmd": "mermaid",
    "meson": "meson",
    "ninja": "ninja",
    "nix": "nix",
    "nqc": "nqc",
    "m": "objc",
    "odin": "odin",
    "org": "org",
    "pas": "pascal",
    "pem": "pem",
    "pl": "perl",
    "pgn": "pgn",
    "po": "po",
    "pony": "pony",
    "ps1": "powershell",
    "printf": "printf",
    "prisma": "prisma",
    "properties": "properties",
    "proto": "proto",
    "pp": "puppet",
    "purs": "purescript",
    "pymanifest": "pymanifest",
    "qmldir": "qmldir",
    "qml": "qmljs",
    "query": "query",
    "r": "r",
    "rkt": "racket",
    "re": "re2c",
    "inputrc": "readline",
    "requirements.txt": "requirements",
    "ron": "ron",
    "rst": "rst",
    "scm": "scheme",
    "smali": "smali",
    "smithy": "smithy",
    "sol": "solidity",
    "rq": "sparql",
    "nut": "squirrel",
    "star": "starlark",
    "svelte": "svelte",
    "td": "tablegen",
    "tcl": "tcl",
    "test": "test",
    "thrift": "thrift",
    "toml": "toml",
    "twig": "twig",
    "typ": "typst",
    "rules": "udev",
    "ungram": "ungrammar",
    "tal": "uxntal",
    "v": "v",
    "sv": "verilog",
    "vhd": "vhdl",
    "vhdl": "vhdl",
    "wgsl": "wgsl",
    "XCompose": "xcompose",
    "yuck": "yuck",
    "zig": "zig",
    "magik": "magik"
}

def is_top_level_node(node: Node) -> bool:
    """Check if a node is a top-level definition (class, function, etc.)"""
    node_type = node.type
    return node_type in {
        'class_definition', 'function_definition',  # Python
        'method_definition', 'class_declaration',   # JavaScript/TypeScript
        'struct_definition', 'impl_item',           # Rust
        'function_item', 'trait_definition',        # Rust
        'method_declaration', 'class_declaration',  # Java
        'function_declaration', 'interface_declaration',  # TypeScript
        'function', 'class',                        # Generic
    }

def chunk_code(code: str, path: str) -> list[CodeSnippet]:
    """
    Chunk code into semantically meaningful pieces.

    Args:
        code: Source code to chunk
        path: Path to the source file

    Returns:
        List of CodeSnippet objects
    """
    ext = path.split(".")[-1]

    if ext in EXTENSION_TO_LANGUAGE:
        language = EXTENSION_TO_LANGUAGE[ext]
    else:
        # Fallback to naive chunking if tree_sitter fails
        line_count = 40
        overlap = 5      # Added overlap for context
        chunks = naive_chunker(code, line_count, overlap)
        snippets = []
        for idx, chunk in enumerate(chunks):
            end = min((idx + 1) * (line_count - overlap) + overlap, len(code.split("\n")))
            new_snippet = CodeSnippet(
                content=chunk,
                start=idx * (line_count - overlap),
                end=end,
                file_path=path,
            )
            snippets.append(new_snippet)
        return snippets

    try:
        parser = get_parser(language)
        tree = parser.parse(code.encode("utf-8"))

        # Regular chunking
        chunks = chunk_tree(tree, code)
        snippets = []
        for chunk in chunks:
            new_snippet = CodeSnippet(
                content=chunk.extract_lines(code),
                start=chunk.start,
                end=chunk.end,
                file_path=path,
            )
            snippets.append(new_snippet)
        return snippets
    except Exception:
        logging.error(traceback.format_exc())
        # Fallback to naive chunking
        line_count = 40
        overlap = 5
        chunks = naive_chunker(code, line_count, overlap)
        snippets = []
        for idx, chunk in enumerate(chunks):
            end = min((idx + 1) * (line_count - overlap) + overlap, len(code.split("\n")))
            new_snippet = CodeSnippet(
                content=chunk,
                start=idx * (line_count - overlap),
                end=end,
                file_path=path,
            )
            snippets.append(new_snippet)
        return snippets
