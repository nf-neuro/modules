
process DENOISING_NLMEANS {
    tag "$meta.id"
    label 'process_medium'

    container "scilus/scilpy:2.2.2_cpu"

    input:
    tuple val(meta), path(image), path(mask), path(mask_sigma)

    output:
    tuple val(meta), path("*__denoised.nii.gz")     , emit: image
    tuple val(meta), path("*__piesno_mask.nii.gz")  , emit: piesno_mask, optional: true
    path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def gaussian = task.ext.gaussian ? "--gaussian" : ""
    def sigma = task.ext.sigma ? "--sigma $task.ext.sigma" : ""
    def basic_sigma = task.ext.basic_sigma ? "--basic_sigma" : ""
    def piesno = task.ext.piesno ? "--piesno" : ""
    def ncoils = task.ext.number_of_coils ? "--number_coils $task.ext.number_of_coils" : ""
    def sigma_from_all_voxels = task.ext.sigma_from_all_voxels ? "--sigma_from_all_voxels" : ""
    def save_piesno_mask = task.ext.save_piesno_mask ? "--save_piesno_mask ${prefix}__piesno_mask.nii.gz" : ""
    def nthreads = task.ext.single_thread ? 1 : task.cpus
    def args = ["--processes $nthreads"]
    if (mask) args += ["--mask_denoise $mask"]
    if (mask_sigma) args += ["--mask_sigma $mask_sigma"]

    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    scil_denoising_nlmeans $image ${prefix}__denoised.nii.gz \
        $gaussian $sigma $basic_sigma $piesno $ncoils $save_piesno_mask $sigma_from_all_voxels ${args.join(" ")}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_denoising_nlmeans -h

    touch ${prefix}__denoised.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
