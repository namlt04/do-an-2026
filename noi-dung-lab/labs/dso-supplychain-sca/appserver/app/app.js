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

// Trang ghi chu render bang EJS 3.1.6 (CVE-2022-29078). Du lieu nguoi dung
// (req.query) duoc dua truc tiep lam options/locals cho res.render -> cho phep
// o nhiem options va thuc thi ma khi render template.
app.get('/notes', (req, res) => {
  res.render('page', req.query);
});

app.listen(3000, '0.0.0.0', () => console.log('vuln-notes listening on 3000'));
