
BEGIN;

-- Employment types
INSERT INTO master.employment_type (code, name)
VALUES
    ('full_time',  'Full-time'),
    ('part_time',  'Part-time'),
    ('contract',   'Contract'),
    ('internship', 'Internship'),
    ('temporary',  'Temporary'),
    ('freelance',  'Freelance')
ON CONFLICT (code) DO NOTHING;

-- Work location types
INSERT INTO master.work_type (code, name)
VALUES
    ('on_site', 'On-site'),
    ('remote',  'Remote'),
    ('hybrid',  'Hybrid')
ON CONFLICT (code) DO NOTHING;

-- Qualification categories
INSERT INTO master.qualification (name, qualification_level)
VALUES
    ('Secondary School',       'secondary'),
    ('Higher Secondary',       'higher_secondary'),
    ('Diploma',                'diploma'),
    ('Undergraduate',          'undergraduate'),
    ('Postgraduate',           'postgraduate'),
    ('Doctorate',              'doctorate'),
    ('Professional',           'professional'),
    ('Other',                  'other')
ON CONFLICT (name, qualification_level) DO NOTHING;

-- Initial industry catalogue
INSERT INTO master.industry (name, normalized_name)
VALUES
    ('Information Technology',       'information technology'),
    ('Finance and Banking',          'finance and banking'),
    ('Healthcare',                   'healthcare'),
    ('Education',                    'education'),
    ('Manufacturing',                'manufacturing'),
    ('Retail and E-commerce',        'retail and e-commerce'),
    ('Consulting',                   'consulting'),
    ('Telecommunications',           'telecommunications'),
    ('Media and Entertainment',      'media and entertainment'),
    ('Transportation and Logistics', 'transportation and logistics'),
    ('Construction and Real Estate', 'construction and real estate'),
    ('Hospitality and Tourism',      'hospitality and tourism')
ON CONFLICT (normalized_name) DO NOTHING;

-- Initial skill catalogue
INSERT INTO master.skill (name, normalized_name)
VALUES
    ('C',                  'c'),
    ('C++',                'c++'),
    ('C#',                 'c#'),
    ('Java',               'java'),
    ('JavaScript',         'javascript'),
    ('TypeScript',         'typescript'),
    ('Python',             'python'),
    ('Go',                 'go'),
    ('Rust',               'rust'),
    ('SQL',                'sql'),
    ('PostgreSQL',         'postgresql'),
    ('MySQL',              'mysql'),
    ('MongoDB',            'mongodb'),
    ('Redis',              'redis'),
    ('HTML',               'html'),
    ('CSS',                'css'),
    ('React',              'react'),
    ('Next.js',            'next.js'),
    ('Node.js',            'node.js'),
    ('Express.js',         'express.js'),
    ('NestJS',             'nestjs'),
    ('Docker',             'docker'),
    ('Kubernetes',         'kubernetes'),
    ('Git',                'git'),
    ('Linux',              'linux'),
    ('REST API Development','rest api development'),
    ('GraphQL',            'graphql'),
    ('Data Structures',    'data structures'),
    ('Algorithms',         'algorithms'),
    ('System Design',      'system design'),
    ('Communication',      'communication'),
    ('Problem Solving',    'problem solving'),
    ('Project Management', 'project management'),
    ('Teamwork',           'teamwork')
ON CONFLICT (normalized_name) DO NOTHING;

COMMIT;
