process IMAGE_ANTSMATH {
    tag "$meta.id"
    label 'process_medium'

    container "scilus/scilus:2.2.2"

    input:
        tuple val(meta), path(input)

    output:
        tuple val(meta), path("*.nii.gz"), emit: image
        path "versions.yml",               emit: versions

    when:
        task.ext.when == null || task.ext.when

    script:
    def operations = ['MajorityVoting', 'm']
    assert task.ext.operation in operations : "Invalid operation: ${task.ext.operation}. " +
        "Must be one of ${operations}"

    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: task.ext.operation

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${task.ext.single_thread ? 1 : task.cpus}
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    ImageMath 3 ${prefix}_${suffix}.nii.gz ${task.ext.operation} $input

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: task.ext.operation

    """
    set +e
    function handle_code () {
    local code=\$?
    ignore=( 1 )
    [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR
    
    ImageMath

    touch ${prefix}_${suffix}.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
    END_VERSIONS
    """
}
