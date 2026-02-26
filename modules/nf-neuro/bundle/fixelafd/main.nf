process BUNDLE_FIXELAFD {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.1_cpu"

    input:
        tuple val(meta), path(bundles), path(fodf)

    output:
        tuple val(meta), path("*_afd_metric.nii.gz"), emit: fixel_afd
        path "versions.yml"                         , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    for bundle in $bundles;
        do\
        bname=\$(basename \${bundle} .trk)
        bname=\${bname/${prefix}__/}
        bname=\${bname/__cleaned/}
        scil_bundle_mean_fixel_afd \$bundle $fodf ${prefix}__\${bname}_afd_metric.nii.gz
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_bundle_mean_fixel_afd -h

    touch ${prefix}_test_afd_metric.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
