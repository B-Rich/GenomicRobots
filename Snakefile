import os
import pandas as pd
import yaml

config.update(yaml.load(open('config.yaml')))
SAMPLES_FILE = config['samples_table']

if 'SESSION_ID' not in os.environ:
    SNPS_FILE = 'testsnps.in'
else:
    SNPS_FILE = config['tmp_pattern'].format(SESSION_ID=os.environ['SESSION_ID'])

SAMPLES = pd.read_table(
        SAMPLES_FILE,
        comment="#",
        index_col=0,
        names=['sampleid', 'path']
)['path'].to_dict()

sample_ids = list(SAMPLES.keys())
fastqs = list(SAMPLES.values())

# TODO: what thresh makes sense?
MIN_MAF = 0.01

targets = [
    fastqs,
    expand('{sample_id}/answer.txt', sample_id=sample_ids),
    'answer.txt'
]


rule all:
    input: targets


rule pre_filter_ids:
    input:
        rsids=SNPS_FILE
    output: 'filtered_rsids.txt'
    shell:
        'python filter_ids.py '
        '--ids {input} '
        '--thresh {MIN_MAF} '
        '> {output}'


# PSST uses IDs without the "rs", so we strip those here.
rule strip_rs:
    input: 'filtered_rsids.txt'
    output: 'stripped_rs.list'
    shell:
        'sed "s/^rs//g" {input} > {output}'


rule psst:
    input:
        rsids='stripped_rs.list',
        fastq=lambda wildcards: SAMPLES[wildcards.sampleid]
    output:
        '{sampleid}/results.tsv'
    threads: 8
    conda:  'py2env.yaml'
    shell:
        'mkdir -p {wildcards.sampleid} && cd {wildcards.sampleid} &&'
        'PATH=/home/ubuntu/daler/PSST:/home/ubuntu/bballew/ncbi-magicblast-1.2.0/bin/:$PATH '
        'psst.sh -f {input.fastq} -n ../{input.rsids} -d . -e none@example.com -t {threads} -p {threads}'

rule post_psst:
    input:
        rsids='stripped_rs.list',
        psst='{sampleid}/results.tsv'
    output: '{sampleid}/out.csv'
    shell:
        'python psst_to_matrix.py '
        '{input.rsids} '
        '{SAMPLES_FILE} '
        '{input.psst} '


rule answer:
    input: '{sampleid}/out.csv',
    output: '{sampleid}/answer.txt'
    run:
        # TODO: actually write this
        shell('touch {output}')


rule aggregate:
    input: expand('{sampleid}/answer.txt', sampleid=sample_ids)
    output: 'answer.txt'
    run:

        # TODO: this is where we have to make various decisions about what/how
        # to report
        for i in input:
            df = pd.read_table(i)
        shell('touch {output}')

# vim: ft=python