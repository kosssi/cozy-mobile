var page = require('webpage').create();
page.open('file:///home/simonc/dev/work/cozy/cozy-mobile/www-src/test/functional/assets/_tests.html', function(status) {
    console.log(status);
    var title = page.evaluate(function() {
        return document.title;
    });
    console.log('Page title is ' + title);
    console.log($('.failures'));
    phantom.exit();
});
