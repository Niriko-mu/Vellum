'use strict';
let book, rendition;
const send = data => Vellum.postMessage(JSON.stringify(data));
const normalize = text => Array.from(text.replace(/\s+/g, '')).slice(0, 80).join('');
window.startBook = async function(config) {
  try {
    book = ePub(config.url, {openAs: 'opf'});
    await book.ready;
    rendition = book.renderTo('reader', {
      width: '100%', height: '100%', manager: 'default', flow: 'paginated',
      allowScriptedContent: false, allowPopups: false, spread: 'none'
    });
    rendition.on('relocated', async location => {
      let text = '';
      try {
        const range = await book.getRange(location.start.cfi);
        let node = range.startContainer;
        if (node.nodeType === 3) node = node.parentElement;
        const paragraph = node.closest('p,li,h1,h2,h3,h4,h5,h6,td,blockquote') || node;
        text = normalize(paragraph.textContent || '');
      } catch (_) {}
      send({type:'position', cfi:location.start.cfi, spine:location.start.index, text});
    });
    rendition.on('selected', async (cfi, contents) => {
      const range = await book.getRange(cfi);
      send({type:'selection', cfi, text:range.toString()});
      contents.window.getSelection().removeAllRanges();
    });
    rendition.on('displayError', error => send({type:'error', message:String(error)}));
    const navigation = await book.loaded.navigation;
    const flatten = (items, depth = 0) => items.flatMap(item => [
      {title:item.label.trim(), href:item.href, depth}, ...flatten(item.subitems || [], depth + 1)
    ]);
    send({type:'toc', entries:flatten(navigation.toc)});
    let target = config.cfi || Math.min(config.spine || 0, book.spine.length - 1);
    await rendition.display(target);
    // When switching from reflow, use an exact text anchor in the displayed
    // section. No book-wide locations generation or full-document scan.
    if (!config.cfi && config.text) {
      const wanted = normalize(config.text);
      for (const contents of rendition.getContents()) {
        const elements = contents.document.querySelectorAll('p,li,h1,h2,h3,h4,h5,h6,td,blockquote');
        for (const element of elements) {
          if (normalize(element.textContent || '') === wanted) {
            const range = contents.document.createRange();
            range.selectNodeContents(element);
            await rendition.display(contents.cfiFromRange(range));
            break;
          }
        }
      }
    }
    for (const note of config.notes || []) rendition.annotations.highlight(note.cfi, {});
    send({type:'ready'});
  } catch (error) {send({type:'error', message:String(error)});}
};
window.turn = direction => direction > 0 ? rendition.next() : rendition.prev();
window.go = target => rendition.display(target);
window.mark = cfi => rendition.annotations.highlight(cfi, {});
window.readerLocation = () => rendition ? JSON.stringify(rendition.currentLocation()) : '{}';
window.addEventListener('pagehide', () => {if(book) book.destroy();});
