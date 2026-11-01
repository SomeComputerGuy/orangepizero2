import sys,re,html
t=open(sys.argv[1],encoding='utf-8',errors='replace').read()
t=re.sub(r'<script.*?</script>','',t,flags=re.S); t=re.sub(r'<style.*?</style>','',t,flags=re.S)
t=re.sub(r'</t[rd]>|</th>|<br\s*/?>',' | ',t); t=re.sub(r'</(p|h\d|li|tr)>','\n',t)
t=re.sub(r'<[^>]+>','',t); t=html.unescape(t)
print('\n'.join(l.strip() for l in t.split('\n') if l.strip()))
