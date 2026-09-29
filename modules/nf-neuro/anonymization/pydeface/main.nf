process PYDEFACE {
    tag "${meta.id}"
    label "process_medium"

    container "community.wave.seqera.io/library/procps-ng_pydeface_fsl-flirt:223b251c6cae5c95"
    containerOptions {
        workflow.containerEngine == 'docker' ? '--entrypoint ""' : ''
    }

    input:
    tuple val(meta), path(nifti)

    output:
    tuple val(meta), path("*_defaced.nii.gz")   , emit: defaced
    path "versions.yml"                         , emit: versions, topic: "versions"

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    set -euo pipefail
    export OMP_NUM_THREADS="${task.cpus}"
    export OMP_THREADS="${task.cpus}"
    export FSLDIR="\${FSLDIR:-/opt/conda}"
    export PATH="\${FSLDIR}/share/fsl/bin:\${FSLDIR}/bin:\${PATH}"

    pydeface $nifti --outfile ${prefix}_defaced.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pydeface: \$(pydeface --version 2>&1 | grep -oE '[0-9]+[.][0-9]+([.][0-9]+)?' | head -n 1 || true)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_defaced.nii.gz

    pydeface --help

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pydeface: \$(pydeface --version 2>&1 | grep -oE '[0-9]+[.][0-9]+([.][0-9]+)?' | head -n 1 || true)
    END_VERSIONS
    """
}
