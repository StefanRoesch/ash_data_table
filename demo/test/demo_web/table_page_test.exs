defmodule DemoWeb.TablePageTest do
  # The helpers read a page where a person sees it: what a `<.portal>`
  # renders into a template is read at its target, without the portal's
  # wrapper, which takes no part in the layout (stage 5 of the refactor).
  use ExUnit.Case, async: true
  import DemoWeb.TablePage

  test "the content of a portal is read where the browser shows it" do
    html = """
    <div id="task"><div id="task-grid" data-ash-data-table phx-target="1"></div>
    <template id="p1" data-phx-portal="#spot"><div id="_lv_portal_wrap_p1"><div id="task-picker" data-question="Q?"><h2 id="task-picker-title">Pick</h2><template id="p2" data-phx-portal="[id='inner']"><div id="_lv_portal_wrap_p2"><span id="deep">deep</span></div></template><div><button>Cancel</button></div></div></div></template>
    <template id="task-editor-title" data-editor="text"><input type="text"/></template>
    </div><div id="spot"><p id="inner"></p></div>
    """

    assert picker(html).heading == "Pick"
    assert picker(html).question == "Q?"
    assert picker(html).buttons == ["Cancel"]
    assert text(html, "#spot > #task-picker > h2") == "Pick"
    assert text(html, "#inner #deep") == "deep"
    assert editor(html, "task", "title").control == "text"
    assert picker("<div id=\"x\"></div>") == nil
    # a query that does not move it finds nothing
    refute Enum.any?(LazyHTML.query(LazyHTML.from_fragment(html), "#task-picker"))
  end

  test "the content of a portal is read where the browser shows it, in an attached table" do
    html = """
    <div id="task"><div id="task-grid" data-ash-data-table></div>
    <template id="p1" data-phx-portal="#spot"><div id="_lv_portal_wrap_p1"><div id="task-picker" data-question="Q?"><h2 id="task-picker-title">Pick</h2><template id="p2" data-phx-portal="[id='inner']"><div id="_lv_portal_wrap_p2"><span id="deep">deep</span></div></template><div><button>Cancel</button></div></div></div></template>
    <template id="task-editor-title" data-editor="text"><input type="text"/></template>
    </div><div id="spot"><p id="inner"></p></div>
    """

    assert picker(html).heading == "Pick"
    assert picker(html).question == "Q?"
    assert picker(html).buttons == ["Cancel"]
    assert text(html, "#spot > #task-picker > h2") == "Pick"
    assert text(html, "#inner #deep") == "deep"
    assert editor(html, "task", "title").control == "text"
    assert picker("<div id=\"x\"></div>") == nil
    # a query that does not move it finds nothing
    refute Enum.any?(LazyHTML.query(LazyHTML.from_fragment(html), "#task-picker"))
  end
end
