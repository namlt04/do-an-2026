const express = require('express');
const path = require('path');

const app = express();
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

app.get('/', (req, res) => {
  res.json({ app: 'vuln-notes', version: '1.0.0', endpoints: ['/api/health', '/notes?name='] });
});

app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

// Notes page rendered with EJS 3.1.6 (CVE-2022-29078). User-supplied data
// (req.query) is passed directly as options/locals to res.render -> allowing
// options pollution and code execution when the template is rendered.
app.get('/notes', (req, res) => {
  res.render('page', req.query);
});

app.listen(3000, '0.0.0.0', () => console.log('vuln-notes listening on 3000'));
