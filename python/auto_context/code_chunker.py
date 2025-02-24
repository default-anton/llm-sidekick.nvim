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
        else:
            raise NotImplementedError()

    def __len__(self) -> int:
        # i.e. Span(a, b) = b - a
        return self.end - self.start

def non_whitespace_len(s: str) -> int:  # new len function
    return len(re.sub("\s", "", s))

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
    max_chars=512 * 3,
    coalesce=50,  # Any chunk less than 50 characters long gets coalesced with the next chunk
) -> list[Span]:

    # 1. Recursively form chunks based on the last post (https://docs.sweep.dev/blogs/chunking-2m-files)
    def chunk_node(node: Node) -> list[Span]:
        chunks: list[Span] = []
        current_chunk: Span = Span(node.start_byte, node.start_byte)
        node_children = node.children
        for child in node_children:
            if child.end_byte - child.start_byte > max_chars:
                chunks.append(current_chunk)
                current_chunk = Span(child.end_byte, child.end_byte)
                chunks.extend(chunk_node(child))
            elif child.end_byte - child.start_byte + len(current_chunk) > max_chars:
                chunks.append(current_chunk)
                current_chunk = Span(child.start_byte, child.end_byte)
            else:
                current_chunk += Span(child.start_byte, child.end_byte)
        chunks.append(current_chunk)
        return chunks

    chunks = chunk_node(tree.root_node)

    # 2. Filling in the gaps
    if len(chunks) == 0:
        return []
    if len(chunks) < 2:
        end = get_line_number(chunks[0].end, source_code)
        return [Span(0, end)]
    for i in range(len(chunks) - 1):
        chunks[i].end = chunks[i + 1].start
    chunks[-1].end = tree.root_node.end_byte

    # 3. Combining small chunks with bigger ones
    new_chunks = []
    current_chunk = Span(0, 0)
    for chunk in chunks:
        current_chunk += chunk
        if non_whitespace_len(
            current_chunk.extract(source_code)
        ) > coalesce and "\n" in current_chunk.extract(source_code):
            new_chunks.append(current_chunk)
            current_chunk = Span(chunk.end, chunk.end)
    if len(current_chunk) > 0:
        new_chunks.append(current_chunk)

    # 4. Changing line numbers
    line_chunks = [
        Span(
            get_line_number(chunk.start, source_code),
            get_line_number(chunk.end, source_code),
        )
        for chunk in new_chunks
    ]

    # 5. Eliminating empty chunks
    line_chunks = [chunk for chunk in line_chunks if len(chunk) > 0]

    # 6. Coalescing last chunk if it's too small
    if len(line_chunks) > 1 and len(line_chunks[-1]) < coalesce:
        line_chunks[-2] += line_chunks[-1]
        line_chunks.pop()

    return line_chunks

def naive_chunker(code: str, line_count: int = 25, overlap: int = 0):
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

def chunk_code(code: str, path: str) -> list[CodeSnippet]:
    ext = path.split(".")[-1]

    if ext in EXTENSION_TO_LANGUAGE:
        language = EXTENSION_TO_LANGUAGE[ext]
    else:
        # Fallback to naive chunking if tree_sitter fails
        line_count = 30
        overlap = 0
        chunks = naive_chunker(code, line_count, overlap)
        snippets = []
        for idx, chunk in enumerate(chunks):
            end = min((idx + 1) * (line_count - overlap), len(code.split("\n")))
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
        return []
