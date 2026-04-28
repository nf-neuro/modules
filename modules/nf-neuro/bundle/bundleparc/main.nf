process BUNDLE_BUNDLEPARC {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:dev"

    input:
    tuple val(meta), path(fodf), path(checkpoint)

    output:
    tuple val(meta), path("*__*.nii.gz"), emit: labels
    path "versions.yml"              , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def args = []
    if ( task.ext.nb_pts ) args += ["--nb_pts $task.ext.nb_pts"]
    if ( task.ext.mm ) args += ["--mm $task.ext.mm"]
    if ( task.ext.keep_biggest ) args += ["--keep_biggest_blob"]
    if ( task.ext.min_blob_size ) args += ["--min_blob_size $task.ext.min_blob_size"]
    if ( task.ext.half ) args += ["--half_precision"]
    if ( task.ext.continuous ) args += ["--continuous"]
    if ( task.ext.bundles ) args += ["--bundles $task.ext.bundles"]
    if ( task.ext.sh_basis && task.ext.sh_basis != "descoteaux07" ) {
        error "Unsupported SH basis '${task.ext.sh_basis}'. Only 'descoteaux07' is currently supported."
    }

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${task.ext.single_thread ? 1 : task.cpus}
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    scil_fodf_bundleparc $fodf --out_prefix ${prefix}__ \
        ${args.join(' ')} \
        --out_dir tmp --checkpoint $checkpoint -v DEBUG
    mv tmp/*gz .
    rm -r tmp

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

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}

