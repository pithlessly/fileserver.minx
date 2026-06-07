# Minx static file server

This is the WIP next-generation file server for my homelab (minx). Replacing nginx's built-in static file server, it provides prettier directory indexes and code listings with [arborium](https://github.com/bearcove/arborium/)-based syntax highlighting.

A few other discrepancies with nginx's file server:

- It responds to `/dir` with the content of `/dir/index.html` if the latter exists.
- It doesn't allow symlinks outside of the filesystem root.

Planned features:

- A more flexible "object store" style API under `/objects`
- Generate redirects for symlinks (or maybe only certain ones)
- Integration with notiondemotion (send PDF page count as a header)
- Render markdown files with pandoc
- Cache (in-memory) the results of syntax highlighting and pretty-printing
