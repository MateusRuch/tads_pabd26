drop table if exists funcionario cascade; 
drop table if exists departamento cascade;
-- obs: 
-- drop table: Apaga permanentemente a estrutura da tabela e todos os seus dados
-- if exists: ignorará o comando caso não exista a tabela.
-- cascade: força a remoção elimitando automaticamente qualquer dependencia vinculada a essas tabelas (chaves estrangeiras,views...) de outras partes do sistema.

create table funcionario(  -- Cria tabela funcionário:
    cpf char(11) primary key, -- texto fixo(char) de 11 caracteres, é uma chave primária. (único e obrigatório.)
    pnome varchar(50) not null, -- texto com limite (varchar) de 50 caracteres.
    unome varchar(50) not null, -- not null: torna o preenchimento obrigatório.
    email varchar(50) unique, -- unique: impedimento de emails repetidos
    endereco varchar(100) default 'Macau-RN', -- default: define um valor padrão caso o campo não seja inserido.
    salario numeric(7,2), -- numero decimal de alta precisão (até 7 dígitos.)
    data_nasc date, -- Campo de data no formato AAA/MM/DD
    sexo char(1),
    cpf_supervisor char(11),
    numero_departamento smallint, -- número inteiro pequeno.

    constraint funcionario_salario_check -- constraint: regras de restrição
    check (salario >= 2000 and salario <= 15000),

    constraint funcionario_sexo_check
    check (sexo in ('m', 'f', 'o', 'M', 'F', 'O'))
);

create table departamento(
    numero smallint primary key,
    nome varchar(50) unique,
    cpf_gerente char(11),
    data_ini date not null
);

-- Adicionar restrição FOREIGN KEY
alter table funcionario -- alter table: modifica uma tabela que já foi criada previamente no banco. 
add constraint funcionario_num_dep_fk -- Adiciona uma nova regra de integridade e define para ela um nome único
foreign key (numero_departamento) -- especifica a coluna (numero_departamento) como chave estrangeira 
references departamento(numero) -- apotna para a chave primária (numero) da tabela departamento.
-- obs: estabeleceu-se o relacionamento oficial entre as tabelas: funcionaro e departamento.

-- no action, set null, restrict, cascade, set default
on delete no action -- impede que um departamento seja apagado se houver funcionários vinculados a ele. O banco lança um erro e cancela a exclusão.
on update cascade; -- Se o número de um departamento for alterado na tabela departamento, o banco atualiza automaticamente o numero_departamento de todos os funcionários associados.
SELECT numero_departamento, -- Select: seleciona a coluna da tabela departamento.
    COUNT(*) AS quantidade_funcionarios -- Conta a quantidade total de linhas (funcionários) e nomeia a coluna.
    group by numero_departamento
FROM funcionario -- define a tabela fonte dos dados. 

-- TO DO: adicionar restrições FK para cpf_supervisor e cpf_gerente
alter table funcionario
add constraint funcionario_cpf_sup_fk
foreign key (cpf_supervisor)
references funcionario(cpf)
-- obs: leitura do código: alteração da tabela funcionario, adição da regra restritiva funcionario_cpf_sup_fk, que será o cpf do supervisor referenciando o cpf do da tabela funcionario

-- no action, set null, restrict, cascade, set default
on delete set null
on update cascade;

alter table departamento
add constraint departamento_cpf_gerente_fk
foreign key (cpf_gerente)
references funcionario(cpf)

-- no action, set null, restrict, cascade, set default
on delete set null -- caso um supervisor seja apagado da tabela, seus subordinados não serão excluídos, a coluna supervisor será null.
on update cascade; -- Se o cpf de um supervisor for modificado, essa alteração será propagada em cascata para a coluna

/*

-- Adicionar um novo atributo
alter table departamento
add column data_ini date; 

-- Alterar um atributo para NOT NULL
alter table departamento
alter column data_ini set not null;

-- Excluir um atributo
-- alter table departamento
-- drop column data_ini;

-- Adicionar um valor padrão DEFAULT
alter table funcionario
alter column endereco set default 'Macau-RN';

-- Excluir um valor padrão DEFAULT
-- alter table funcionario
-- alter column endereco drop default;

-- Adicionar restrição (constraint) CHECK
alter table funcionario
add constraint funcionario_sexo_check
-- check (lower(sexo) in ('m', 'f', 'o'));
check (sexo in ('m', 'f', 'o', 'M', 'F', 'O'));

-- Excluir restrição
alter table funcionario
drop constraint if exists funcionario_sexo_check;

*/