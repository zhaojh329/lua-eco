(function () {
   function getBasePath() {
      var scripts = document.getElementsByTagName('script');
      for (var i = 0; i < scripts.length; i++) {
         var src = scripts[i].getAttribute('src') || '';
         if (src.indexOf('ldoc_search.js') >= 0) {
            return src.replace(/ldoc_search\.js(?:\?.*)?$/, '');
         }
      }
      return '';
   }

   function escapeHtml(text) {
      return String(text || '')
         .replace(/&/g, '&amp;')
         .replace(/</g, '&lt;')
         .replace(/>/g, '&gt;')
         .replace(/"/g, '&quot;')
         .replace(/'/g, '&#39;');
   }

   function normalize(text) {
      return String(text || '').toLowerCase();
   }

   function score(entry, terms) {
      var symbol = normalize(entry.symbol || entry.title);
      var title = normalize(entry.title);
      var module = normalize(entry.module);
      var kind = normalize(entry.kind);
      var summary = normalize(entry.summary);
      var total = 0;

      for (var i = 0; i < terms.length; i++) {
         var term = terms[i];
         var inSymbol = symbol.indexOf(term) >= 0;
         var inTitle = title.indexOf(term) >= 0;
         var inContext = module.indexOf(term) >= 0 || kind.indexOf(term) >= 0 || summary.indexOf(term) >= 0;

         if (!inSymbol && !inTitle && !inContext) {
            return -1;
         }

         if (symbol === term) {
            total += 300;
         } else if (symbol.indexOf(term) === 0) {
            total += 160;
         } else if (inSymbol) {
            total += 80;
         }

         if (inTitle) {
            total += 45;
         }

         if (inContext) {
            total += 12;
         }
      }

      return total;
   }

   function renderResults(items, resultsNode) {
      if (!items.length) {
         resultsNode.innerHTML = '<div class="ldoc-search-empty">No results</div>';
         resultsNode.style.display = 'block';
         return;
      }

      var rows = [];
      for (var i = 0; i < items.length; i++) {
         var row = items[i];
         var meta = [];
         if (row.module) {
            meta.push(row.module);
         }
         if (row.kind) {
            meta.push(row.kind);
         }

         rows.push(
            '<a class="ldoc-search-item" href="' + escapeHtml(resolveUrl(row.url)) + '">' +
               '<span class="ldoc-search-title">' + escapeHtml(row.title || row.symbol || '') + '</span>' +
               '<span class="ldoc-search-meta">' + escapeHtml(meta.join(' | ')) + '</span>' +
            '</a>'
         );
      }

      resultsNode.innerHTML = rows.join('');
      resultsNode.style.display = 'block';
   }

   function hideResults(resultsNode) {
      resultsNode.style.display = 'none';
      resultsNode.innerHTML = '';
   }

   var basePath = '';

   function resolveUrl(url) {
      var value = String(url || '');
      if (/^(?:[a-z]+:|\/|#)/i.test(value)) {
         return value;
      }
      return basePath + value;
   }

   function initSearch() {
      var input = document.getElementById('ldoc-search-input');
      var results = document.getElementById('ldoc-search-results');
      var data = window.ldocSearchData || [];
      basePath = getBasePath();

      if (!input || !results || !Array.isArray(data)) {
         return;
      }

      input.addEventListener('input', function () {
         var query = normalize(input.value).trim();
         if (query.length < 1) {
            hideResults(results);
            return;
         }

         var terms = query.split(/\s+/).filter(Boolean);
         var matches = [];
         for (var i = 0; i < data.length; i++) {
            var entry = data[i];
            var rank = score(entry, terms);
            if (rank >= 0) {
               matches.push({
                  rank: rank,
                  symbol: entry.symbol,
                  title: entry.title,
                  module: entry.module,
                  kind: entry.kind,
                  url: entry.url,
               });
            }
         }

         matches.sort(function (a, b) {
            if (b.rank !== a.rank) {
               return b.rank - a.rank;
            }
            return String(a.title || '').localeCompare(String(b.title || ''));
         });

         renderResults(matches.slice(0, 40), results);
      });

      document.addEventListener('click', function (ev) {
         if (!results.contains(ev.target) && ev.target !== input) {
            hideResults(results);
         }
      });
   }

   if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', initSearch);
   } else {
      initSearch();
   }
}());
