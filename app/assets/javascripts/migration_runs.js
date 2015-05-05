
$(document).ready( function() {
  if ($("body.migration_runs_show").length) {
    check_spinner();
    set_refresh();

    $('#spinner').click( function() {
      clear_refresh();
      $('#spinner').hide();
      $('#pause').show();
    })

    $('#pause').click( function() {
      $('#pause').hide();
      $('#spinner').show();
      set_refresh();
    })

  }
});


function check_spinner() {
  var status = $('#status').text();
  if (status == 'preparing' || status == 'running' || status == 'queued') {
    $('#spinner').show();
  } else {
    $('#spinner').hide();
  }
}

function set_refresh() {
  if ($('#spinner').is(':visible')) {
    $('body').data('reload', setInterval("page_reload();",5000));
  }
}

function clear_refresh() {
  clearInterval($('body').data('reload'));

}

function page_reload(){
  window.location = location.href;
}
