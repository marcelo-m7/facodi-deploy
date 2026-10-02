"""Replay the explicitly authorised editorial consolidation in an Odoo shell.

Run from the facodi-deploy checkout with exec(open(...).read()). This is an
editorial operation, deliberately separate from automatic runtime migrations.
Existing About content and its translations are preserved. Rerunning is safe.
"""
from pathlib import Path
from lxml import etree
import json

website = env['website'].search([('domain', '=', 'https://facodi.com')], limit=1)
assert website and env.cr.dbname == 'facodi', 'This operation targets FACODI only'
root = Path('editorial')
Page = env['website.page'].with_context(lang='en_US')
about = Page.search([('website_id', '=', website.id), ('url', '=', '/about')], limit=1)
assert about, 'Existing editor-owned About page required'
arch = etree.fromstring(about.view_id.arch_db.encode())
wrap = arch.xpath('.//div[@id="wrap"]')[0]
sections = etree.parse(str(root / 'navigation-about-sections.xml')).getroot()
for section in sections:
    if not wrap.xpath('.//*[@id=$section_id]', section_id=section.get('id')):
        wrap.append(section)
about.view_id.write({'arch_db': etree.tostring(arch, encoding='unicode')})

partners = Page.search([('website_id', '=', website.id), ('url', '=', '/partners')], limit=1)
if not partners:
    partners = Page.search([('website_id', '=', website.id), ('url', '=', '/about-ualg')], limit=1)
assert partners, 'Existing UAlg/Partnerships editorial page required'
partners.write({'url': '/partners', 'name': 'FACODI Partnerships', 'website_meta_title': 'Partnerships | FACODI'})
partners.view_id.write({'arch_db': (root / 'navigation-partners.xml').read_text()})

translations = json.loads((root / 'navigation-translations.json').read_text())
for page, key in [(about, 'about'), (partners, 'partners')]:
    page.view_id.update_field_translations('arch_db', translations[key], source_lang='en_US')

redirects = {'/about-ualg': '/partners', '/parceiros': '/partners',
             '/academic-model': '/about#academic-model', '/about-marcelo': '/about#author',
             '/infrastructure': '/about#infrastructure'}
for old, new in redirects.items():
    legacy = Page.search([('website_id', '=', website.id), ('url', '=', old)])
    legacy.write({'is_published': False})
    Rewrite = env['website.rewrite']
    rewrite = Rewrite.search([('website_id', 'in', [False, website.id]), ('url_from', '=', old)], limit=1)
    values = {'name': 'FACODI navigation ' + old, 'website_id': website.id,
              'url_from': old, 'url_to': new, 'redirect_type': '301', 'active': True}
    rewrite.write(values) if rewrite else Rewrite.create(values)
env['website.menu'].with_context(website_id=website.id).facodi_reconcile_navigation()
env.cr.commit()
