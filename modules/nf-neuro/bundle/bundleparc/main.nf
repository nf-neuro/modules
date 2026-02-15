process BUNDLE_BUNDLEPARC {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilus:2.2.0"

    input:
        tuple val(meta), path(fodf), path(checkpoint)

    output:
        tuple val(meta), path("*.nii.gz"),  emit: labels
        path "versions.yml",                emit: versions
        path "*__bundleparc_config.json",   emit: config

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def nb_pts = task.ext.nb_pts ?: 10

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=1
    export OMP_NUM_THREADS=1

    stride="\$( mrinfo -stride $fodf )"
    if [[ "\$stride" == "-1 2 3 4" ]]; then
        scil_fodf_bundleparc $fodf \
            --out_prefix ${prefix}__ \
            --nb_pts ${nb_pts} \
            --out_folder tmp \
            --checkpoint ${checkpoint} \
            --keep_biggest
        mv tmp/* .
        rm -r tmp
    else
        echo "Invalid stride ("\$stride"), must be -1 2 3 4"
        exit 1
    fi
    cat <<-BUNDLEPARC_INFO > ${prefix}__bundleparc_config.json
    {"nb_pts": "${task.ext.nb_pts}"}
    BUNDLEPARC_INFO

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    scil_fodf_bundleparc -h

    touch ${prefix}__AF_left.nii.gz
    ${prefix}__bundleparc_config.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
