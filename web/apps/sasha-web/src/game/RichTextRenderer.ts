import { RichText, TextColor } from '@sasha/type-gen-output/client';

const TEXT_COLORS: Record<TextColor, string> = {
  Red: '#ff5555',
  Green: '#55ff55',
  Blue: '#5555ff',
  Yellow: '#ffff55',
  Cyan: '#55ffff',
  Magenta: '#ff55ff',
  White: '#cccccc',
  BrightWhite: '#ffffff',
  BrightRed: '#ff8888',
  BrightGreen: '#88ff88',
  BrightBlue: '#8888ff',
  BrightYellow: '#ffff88',
  BrightCyan: '#88ffff',
  BrightMagenta: '#ff88ff',
};

const DEFAULT_TEXT_COLOR = '#eaeaea';

export function renderRichTextLine(richText: RichText, container: HTMLElement): void {
  const lineDiv = document.createElement('div');
  lineDiv.className = 'rich-line';

  for (const span of richText) {
    const parts = span.ssText.split('\n');
    for (let i = 0; i < parts.length; i++) {
      if (i > 0) lineDiv.appendChild(document.createElement('br'));
      if (parts[i].length > 0) {
        const el = document.createElement('span');
        el.textContent = parts[i];
        const color = span.ssStyle.tsFgColor;
        el.style.color = color ? (TEXT_COLORS[color] ?? DEFAULT_TEXT_COLOR) : DEFAULT_TEXT_COLOR;
        if (span.ssStyle.tsBold) el.style.fontWeight = 'bold';
        if (span.ssStyle.tsItalic) el.style.fontStyle = 'italic';
        lineDiv.appendChild(el);
      }
    }
  }

  if (lineDiv.childNodes.length === 0) lineDiv.innerHTML = '&nbsp;';
  container.appendChild(lineDiv);
}

export function renderPlainLine(text: string, container: HTMLElement, cssClass?: string): void {
  const lineDiv = document.createElement('div');
  lineDiv.className = 'rich-line';
  if (cssClass) lineDiv.classList.add(cssClass);
  lineDiv.textContent = text;
  container.appendChild(lineDiv);
}
