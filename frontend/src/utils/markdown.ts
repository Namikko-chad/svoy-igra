import MarkdownIt from 'markdown-it'

const md = new MarkdownIt({ html: false, linkify: true })

// Links open in a new tab, without leaking the opener.
const defaultLinkOpen =
  md.renderer.rules.link_open ?? ((tokens, idx, options, _env, self) => self.renderToken(tokens, idx, options))
md.renderer.rules.link_open = (tokens, idx, options, env, self) => {
  const token = tokens[idx]!
  token.attrSet('target', '_blank')
  token.attrSet('rel', 'noopener noreferrer')
  return defaultLinkOpen(tokens, idx, options, env, self)
}

/** CommonMark → HTML. Raw HTML in the source is escaped (html: false). */
export function renderMarkdown(src: string): string {
  return md.render(src ?? '')
}
