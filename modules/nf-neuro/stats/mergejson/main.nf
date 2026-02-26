

process STATS_MERGEJSON {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
    tuple val(meta), path(jsons)

    output:
    tuple val(meta), path("*_stats.json")   , emit: json
    tuple val(meta), path("*_stats.xlsx")   , emit: xlsx
    path "versions.yml"                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${task.ext.prefix}"
    def suffix = task.ext.suffix ? "${task.ext.suffix}_stats" : "stats"
    def per_point = task.ext.per_point ? true : false
    def average_last_layer = task.ext.average_last_layer ? "--average_last_layer" : ""
    def recursive = task.ext.recursive ? "--recursive" : ""
    def no_list = task.ext.no_list ? "--no_list" : ""
    def stats_over_population = task.ext.stats_over_population ? "--stats_over_population" : ""

    """
    if $per_point;
        then
        for json in $jsons
            do scil_json_merge_entries \$json \${json/.json/_avg.json} --remove_parent_key --recursive $average_last_layer
        done
            scil_json_merge_entries *_avg.json ${prefix}.json --recursive
    else
        scil_json_merge_entries $jsons ${prefix}.json $no_list $recursive
    fi

    scil_json_harmonize_entries ${prefix}.json ${prefix}_${suffix}.json -f -v --sort_keys
    scil_json_convert_entries_to_xlsx ${prefix}_${suffix}.json ${prefix}_${suffix}.xlsx $stats_over_population

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def suffix = task.ext.first_suffix ? "${task.ext.first_suffix}_stats" : "_stats"
    def prefix = task.ext.prefix ?: "${task.ext.prefix}"

    """
    scil_json_merge_entries -h
    scil_json_harmonize_entries -h
    scil_json_convert_entries_to_xlsx -h

    touch ${prefix}_${suffix}.json
    touch ${prefix}_${suffix}.xlsx

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
