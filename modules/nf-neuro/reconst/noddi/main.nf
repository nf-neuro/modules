process RECONST_NODDI {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilpy:2.2.0_cpu"

    input:
        tuple val(meta), path(dwi), path(bval), path(bvec), path(mask), path(kernels), val(para_diff), val(iso_diff)

    output:
        tuple val(meta), path("*__fit_dir.nii.gz")      , emit: dir, optional: true
        tuple val(meta), path("*__fit_FWF.nii.gz")      , emit: fwf, optional: true
        tuple val(meta), path("*__fit_NDI.nii.gz")      , emit: ndi, optional: true
        tuple val(meta), path("*__fit_ECVF.nii.gz")     , emit: ecvf, optional: true
        tuple val(meta), path("*__fit_ODI.nii.gz")      , emit: odi, optional: true
        path("kernels")                                 , emit: kernels, optional: true
        path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def para_diff_str = task.ext.para_diff ? "--para_diff " + task.ext.para_diff : para_diff ? "--para_diff " + para_diff : ""
    def iso_diff_str = task.ext.iso_diff ? "--iso_diff " + task.ext.iso_diff : iso_diff ? "--iso_diff " + iso_diff : ""
    def lambda1 = task.ext.noddi_lambda1 ? "--lambda1 " + task.ext.noddi_lambda1 : ""
    def lambda2 = task.ext.noddi_lambda2 ? "--lambda2 " + task.ext.noddi_lambda2 : ""
    def nb_threads = task.ext.nb_threads ? "--processes " + task.ext.nb_threads : ""
    def b_thr = task.ext.b_thr ? "--tolerance " + task.ext.b_thr : ""
    def set_kernels = kernels ? "--load_kernels $kernels" : "--save_kernels kernels/"
    def set_mask = mask ? "--mask $mask" : ""
    def compute_only = task.ext.compute_only && !kernels ? "--compute_only" : ""

    """

    ## Check if data are multi-shell based on b-values and set number of clusters accordingly
    # Set tolerance threshold (default 40 if not specified)
    b_threshold=${task.ext.b_thr ?: 40}

    # Load sorted values - handle both space and newline separated b-values
    vals=(\$(cat "$bval" | tr ' ' '\n' | awk '{print int(\$1 + 0.5)}' | sort -n | uniq))

    clusters=1
    uniq_bvals=("\${vals[0]}")

    for ((i=1; i<\${#vals[@]}; i++)); do
        if (( \${vals[\$i]} - \${vals[\$i-1]} > \$b_threshold )); then
            ((clusters++))
            uniq_bvals+=("\${vals[\$i]}")
        fi
    done

    if [ \$clusters -lt 3 ]; then
        echo "Error: NODDI reconstruction requires multi-shell data (at least 2 non-zero b-value shells). Detected only \$clusters shell(s) with b-values: \${uniq_bvals[@]}"
        exit 1
    else
        echo "Detected \$clusters unique b-value shells: \${uniq_bvals[@]}"
    fi

    # Set home directory. This is problematic if the container is run
    # with non-root user which does not create a home directory, whilst
    # AMICO attempts to write in the home directory, raising an error.
    export HOME=/tmp

    scil_NODDI_maps $dwi $bval $bvec $para_diff_str $iso_diff_str $lambda1 \
        $lambda2 $nb_threads $b_thr $set_mask $set_kernels --skip_b0_check $compute_only

    if [ -z "${compute_only}" ];
    then
        mv results/fit_dir.nii.gz ${prefix}__fit_dir.nii.gz
        mv results/fit_NDI.nii.gz ${prefix}__fit_NDI.nii.gz # ICVF -> NDI
        mv results/fit_FWF.nii.gz ${prefix}__fit_FWF.nii.gz # ISOVF/FISO -> FWF
        mv results/fit_ODI.nii.gz ${prefix}__fit_ODI.nii.gz # OD -> ODI

        scil_volume_math subtraction 1 ${prefix}__fit_FWF.nii.gz ${prefix}__fit_ECVF.nii.gz

        rm -rf results
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    scil_NODDI_maps -h
    scil_volume_math -h

    mkdir kernels

    touch "${prefix}__fit_dir.nii.gz"
    touch "${prefix}__fit_FWF.nii.gz"
    touch "${prefix}__fit_NDI.nii.gz"
    touch "${prefix}__fit_ECVF.nii.gz"
    touch "${prefix}__fit_ODI.nii.gz"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
