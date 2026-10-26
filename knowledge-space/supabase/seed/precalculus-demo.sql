-- Hand-curated illustrative pilot, NOT an official curricular mapping.
insert into public.ks_entities (stable_key,kind,label,definition,domain_weights,granularity,source_uri,status) values
('demo:functions','concept','Funções','Relação entre entradas e saídas de uma função.','{"mathematics":0.95,"nature":0.05}',1,'demo://precalculus','approved'),
('demo:domain-range','concept','Domínio e imagem','Conjuntos de entrada e de valores possíveis de uma função.','{"mathematics":1}',2,'demo://precalculus','approved'),
('demo:graphs','concept','Gráficos de funções','Representação visual de relações entre variáveis.','{"mathematics":0.85,"nature":0.15}',2,'demo://precalculus','approved'),
('demo:limits','concept','Limites','Comportamento de uma função quando a variável se aproxima de um valor.','{"mathematics":0.95,"nature":0.05}',2,'demo://precalculus','approved'),
('demo:continuity','concept','Continuidade','Propriedade de funções sem saltos num ponto ou intervalo.','{"mathematics":0.9,"nature":0.1}',3,'demo://precalculus','approved'),
('demo:derivatives','concept','Derivadas','Taxa de variação instantânea de uma função.','{"mathematics":0.78,"nature":0.22}',3,'demo://precalculus','approved'),
('demo:rates','concept','Taxas de variação','Descrição quantitativa de como uma grandeza muda.','{"mathematics":0.65,"nature":0.3,"humanities":0.05}',2,'demo://precalculus','approved'),
('demo:velocity','concept','Velocidade instantânea','Taxa de mudança da posição em relação ao tempo.','{"mathematics":0.35,"nature":0.65}',3,'demo://precalculus','approved'),
('demo:marginal','concept','Análise marginal','Variações incrementais aplicadas à economia.','{"mathematics":0.48,"humanities":0.52}',3,'demo://precalculus','approved'),
('demo:optimization','competency','Modelar e otimizar','Aplicar modelos matemáticos a situações e restrições.','{"mathematics":0.65,"nature":0.2,"humanities":0.15}',3,'demo://precalculus','approved'),
('demo:objective-derivative','objective','Interpretar uma derivada','Interpretar a derivada como taxa de variação em contextos diversos.','{"mathematics":0.8,"nature":0.2}',3,'demo://precalculus','approved')
on conflict (stable_key) do nothing;

with pairs(a,b,t,e) as (values
('demo:functions','demo:domain-range','prerequisite_of','Sequência didática ilustrativa'),
('demo:functions','demo:graphs','prerequisite_of','Sequência didática ilustrativa'),
('demo:functions','demo:limits','prerequisite_of','Sequência didática ilustrativa'),
('demo:limits','demo:continuity','prerequisite_of','Sequência didática ilustrativa'),
('demo:limits','demo:derivatives','prerequisite_of','Sequência didática ilustrativa'),
('demo:derivatives','demo:velocity','applied_in','Aplicação física ilustrativa'),
('demo:derivatives','demo:marginal','applied_in','Aplicação económica ilustrativa'),
('demo:rates','demo:derivatives','applied_in','Interpretação de taxa instantânea'),
('demo:derivatives','demo:optimization','develops_competency','Aplicação interdisciplinar'),
('demo:derivatives','demo:objective-derivative','addresses_objective','Objetivo demonstrativo')
)
insert into public.ks_relations (source_id,target_id,relation_type,evidence,status)
select s.id,t.id,p.t,p.e,'approved' from pairs p
join public.ks_entities s on s.stable_key=p.a
join public.ks_entities t on t.stable_key=p.b
on conflict (source_id,target_id,relation_type) do nothing;
