process BUNDLE_COLORING {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(bundles)

    output:
        tuple val(meta), path("*_colored.trk")      , emit: bundles
        path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def json_str = groovy.json.JsonOutput.toJson(task.ext.colors)
    String bundles_list = bundles.join(", ").replace(',', '')

    """
    echo '$json_str' >> colors.json
    scil_tractogram_assign_uniform_color --dict_colors colors.json \
        --out_suffix "_colored" $bundles_list

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    String bundles_list = bundles.join(", ").replace(',', '')
    """
    for bundle in $bundles_list; do
        ext=\${bundle##*.}
        bname=\$(basename \$bundle .\${ext})
        touch \${bname}_colored.\${ext}
    done

    scil_tractogram_assign_uniform_color -h

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
