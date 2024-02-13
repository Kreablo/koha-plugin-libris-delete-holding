(function () {
    var load = function load () {
        if (window.jQuery) {
            window.jQuery(document).ready(function () {
                init(window.jQuery);
            });
        } else {
            setTimeout(load, 50);
        }
    };

    load();

    var greatestid = function greatestid (containerid, prefix) {
        var max = 0;
        $('#' + containerid + ' input, ' + '#' + containerid + ' select').each(function (index, element) {
            var re = new RegExp(prefix + '(\\d+)');
            var matches = element.id.match(re);
            if (matches) {
                var n = Number(matches[1]);
                if (n > max) {
                    max = n;
                }
            }
        });
        return max;
    };

    var remove_mapping = function remove_mapping (event) {
        event.preventDefault();
        event.stopPropagation();
        var $e = $(event.currentTarget).parent().parent().remove();
    };

    var remove_credentials = function remove_credentials (event) {
        remove_mapping(event);
        credentials_updated();
    };

    var update_id = function update_id ($template, name, idn) {
        $template.find('[name="' + name + '"]').attr('id', name + idn);
        $template.find('label[for="' + name + '"]').attr('for', name + idn);
        $template.find('[name="' + name + '"]').attr('name', name + idn);
    };


    var credentials = function credentials () {
        var a = [];
        $('#libris-credentials-container dl.form-input').each(function (index, element) {
            a.push({
                "name": $(element).find('.credentials-name').val(),
                "id": $(element).find('.credentials-client-id').val(),
                "secret": $(element).find('.credentials-client-secret').val()
            });
        });
        return a;
    };

    var credentials_updated = function credentials_updated () {
        var c = credentials();
        $('#branch-mappings-container select.libris-credentials, #branch-mapping-input-template select.libris-credentials').each(function (index, element) {
            console.log('before ' + $(element).val());
            var current = '';
            if (element.selectedOptions.length === 1) {
                current = element.selectedOptions[0].value;
            }
            console.log('current ' + current);
            var options = Array.from(element.getElementsByTagName('option'));
            for (var i = 1; i < options.length; i += 1) {
                console.log('removing option ' + i + ' options.length: ' + options.length);
                options[i].remove();
            }
            for (var i = 0; i < c.length; i += 1) {
                console.log('adding option ' + i + ' options.length: ' + options.length);
                var opt = document.createElement('option');
                opt.value = c[i].name;
                opt.textContent = c[i].name;
                if (c[i].name === current) {
                    opt.selected = true;
                }
                element.append(opt);
            }
            console.log('after ' + $(element).val());
        });
    };

    var init = function init ($) {
        setTimeout(function () { $('#save-success').fadeOut(); }, 3000);

        $('#branch-mappings-container button.remove-branch-mapping').click(remove_mapping);
        $('#add-branch-mapping').click(function (event) {
            event.preventDefault();
            event.stopPropagation();
            var idn = greatestid('branch-mappings-container', 'branch-mapping-branchcode-') + 1;
            var $template = $('<div />').append($('#branch-mapping-input-template').children().clone());
            update_id($template, 'branch-mapping-branchcode-', idn);
            update_id($template, 'branch-mapping-sigel-', idn);
            update_id($template, 'branch-mapping-credentials-', idn);
            $template.find('button.remove-branch-mapping').click(remove_mapping);
            $('#branch-mappings-container').append($template);
        });

        $('#libris-credentials-container button.remove-credentials').click(remove_credentials);
        $('#add-credentials').click(function (event) {
            event.preventDefault();
            event.stopPropagation();
            var idn = greatestid('libris-credentials-container', 'credentials-name-') + 1;
            var $template = $('<div />').append($('#credentials-input-template').children().clone());
            update_id($template, 'credentials-name-', idn);
            update_id($template, 'credentials-client-id-', idn);
            update_id($template, 'credentials-client-secret-', idn);
            $template.find('input').on('blur', credentials_updated);
            $template.find('button.remove-credentials').click(remove_credentials);
            $('#libris-credentials-container').append($template);
        });
        $('#libris-credentials-container input').on('blur', credentials_updated);
    };
})();
