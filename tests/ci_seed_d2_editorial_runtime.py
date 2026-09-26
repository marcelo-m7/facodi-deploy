"""Seed disposable D2 editorial/browser fixtures for deployment CI."""

website = env["website"].search([], order="id", limit=1)
if not website:
    raise RuntimeError("FACODI Website record is missing")

Page = env["website.page"].with_context(active_test=False)
for key in (
    "facodi_deploy.d2_about_ci",
    "facodi_deploy.d2_contribution_ci",
    "facodi_deploy.d2_policy_ci",
):
    Page.search([("key", "=", key)]).unlink()

about_arch = """
<t t-name="facodi_deploy.d2_about_ci">
  <t t-call="website.layout">
    <div id="wrap">
      <main class="container py-5">
        <section class="facodi-project-story">
          <div class="facodi-project-story__main">
            <p class="facodi-label">Project dossier</p>
            <h1>D2 About integration fixture</h1>
            <p>Editor-owned public page used only by disposable CI.</p>
          </div>
          <aside class="facodi-project-story__note">
            <span class="facodi-label">Open notebook</span>
            <p>Runtime editorial note.</p>
          </aside>
        </section>
        <section class="facodi-principles-ledger mt-4">
          <article class="facodi-principles-ledger__item"><span class="facodi-principles-ledger__index">01</span><h2>Open first</h2><p>Open resources.</p></article>
          <article class="facodi-principles-ledger__item"><span class="facodi-principles-ledger__index">02</span><h2>Context matters</h2><p>Useful context.</p></article>
          <article class="facodi-principles-ledger__item"><span class="facodi-principles-ledger__index">03</span><h2>Review</h2><p>Review before publishing.</p></article>
        </section>
        <ol class="facodi-process-timeline mt-4">
          <li class="facodi-process-timeline__step"><span class="facodi-process-timeline__index">1</span><div><h2>Discover</h2><p>Find a useful path.</p></div></li>
          <li class="facodi-process-timeline__step"><span class="facodi-process-timeline__index">2</span><div><h2>Study</h2><p>Use public resources.</p></div></li>
        </ol>
      </main>
    </div>
  </t>
</t>
""".strip()

contribution_arch = """
<t t-name="facodi_deploy.d2_contribution_ci">
  <t t-call="website.layout">
    <div id="wrap">
      <main class="container py-5">
        <header class="facodi-bulletin-hero">
          <p class="facodi-label">Contribution</p>
          <h1>D2 Contribution integration fixture</h1>
          <p>Submission, review, and publication remain distinct.</p>
        </header>
        <section class="facodi-contribution-board mt-4">
          <article class="facodi-contribution-board__item"><span class="facodi-label">Resource</span><h2>Suggest a public learning resource</h2><a href="/contribuir/recurso">Suggest a resource</a></article>
          <article class="facodi-contribution-board__item"><span class="facodi-label">Context</span><h2>Improve context</h2><a href="/contactus">Contact FACODI</a></article>
          <article class="facodi-contribution-board__item"><span class="facodi-label">Collaboration</span><h2>Build together</h2><a href="/contactus">Start a conversation</a></article>
        </section>
        <ol class="facodi-process-timeline mt-4">
          <li class="facodi-process-timeline__step"><span class="facodi-process-timeline__index">1</span><div><h2>Propose</h2></div></li>
          <li class="facodi-process-timeline__step"><span class="facodi-process-timeline__index">2</span><div><h2>Review</h2></div></li>
          <li class="facodi-process-timeline__step"><span class="facodi-process-timeline__index">3</span><div><h2>Publish</h2></div></li>
        </ol>
      </main>
    </div>
  </t>
</t>
""".strip()

policy_arch = """
<t t-name="facodi_deploy.d2_policy_ci">
  <t t-call="website.layout">
    <div id="wrap">
      <main class="container py-5">
        <article class="facodi-policy-document">
          <header class="facodi-policy-document__header">
            <p class="facodi-label">Policy document</p>
            <h1>D2 Policy integration fixture</h1>
          </header>
          <section>
            <h2>Long-form containment</h2>
            <p><a href="https://example.invalid/this-is-a-deliberately-very-long-path-segment-used-only-to-prove-mobile-overflow-containment-in-disposable-ci">A deliberately long link used only for layout testing</a></p>
            <pre><code>FACODI_D2_POLICY_LONG_CODE_TOKEN_WITHOUT_NATURAL_BREAKS_ABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789</code></pre>
            <table>
              <thead><tr><th>Column one with a longer heading</th><th>Column two with a longer heading</th><th>Column three with a longer heading</th></tr></thead>
              <tbody><tr><td>alpha</td><td>beta</td><td>gamma</td></tr></tbody>
            </table>
          </section>
        </article>
      </main>
    </div>
  </t>
</t>
""".strip()

def make_page(name, key, url, arch):
    page = Page.create({
        "name": name,
        "key": key,
        "type": "qweb",
        "url": url,
        "website_id": website.id,
        "is_published": True,
        "arch": arch,
    })
    if not page.is_published:
        raise RuntimeError(f"{name} was not published")
    return page

about = make_page("D2 About integration fixture", "facodi_deploy.d2_about_ci", "/d2-about-ci", about_arch)
contribution = make_page("D2 Contribution integration fixture", "facodi_deploy.d2_contribution_ci", "/d2-contribution-ci", contribution_arch)
policy = make_page("D2 Policy integration fixture", "facodi_deploy.d2_policy_ci", "/d2-policy-ci", policy_arch)

Blog = env["blog.blog"]
Post = env["blog.post"]
old_blog = Blog.search([("name", "=", "FACODI D2 Deployment Bulletin Fixture"), ("website_id", "=", website.id)])
if old_blog:
    old_blog.blog_post_ids.unlink()
    old_blog.unlink()

blog = Blog.create({"name": "FACODI D2 Deployment Bulletin Fixture", "website_id": website.id})
tag = env["blog.tag"].search([("name", "=", "D2 deployment")], limit=1)
if not tag:
    tag = env["blog.tag"].create({"name": "D2 deployment"})

sparse = Post.create({
    "name": "Sparse D2 deployment post",
    "blog_id": blog.id,
    "content": "<p>Sparse deployment article body.</p>",
    "is_published": True,
})
rich_cover = (
    '{"background-image": "linear-gradient(45deg, #112233, #445566)", '
    '"resize_class": "o_record_has_cover o_half_screen_height", "opacity": "0"}'
)
rich = Post.create({
    "name": "Rich D2 deployment post",
    "subtitle": "A real D2 deployment subtitle",
    "blog_id": blog.id,
    "author_id": env.user.id,
    "tag_ids": [(4, tag.id)],
    "content": "<h2>Rich deployment section</h2><p>Rich deployment article body.</p>",
    "is_published": True,
    "cover_properties": rich_cover,
})

print("FACODI_D2_ABOUT=/d2-about-ci")
print("FACODI_D2_CONTRIBUTION=/d2-contribution-ci")
print("FACODI_D2_POLICY=/d2-policy-ci")
print("FACODI_D2_RICH_POST=" + rich.website_url)
print("FACODI_D2_SPARSE_POST=" + sparse.website_url)
env.cr.commit()
