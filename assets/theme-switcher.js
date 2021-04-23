// @license magnet:?xt=urn:btih:d3d9a9a6595521f9666a5e94cc830dab83b65699&dn=expat.txt Expat

document.getElementById("theme-switch").addEventListener('change', function() {
    localStorage.setItem('theme', this.checked ? 'dark' : 'light');
});

(function () {
    document.getElementById("theme-switch").checked = localStorage.getItem('theme') === 'dark';
})();

// @license-end
