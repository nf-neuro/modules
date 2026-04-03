process PREPROC_N4 {
    tag "$meta.id"
    label 'process_medium'
    label "process_high_memory"

    container "mrtrix3/mrtrix3:3.0.5"

    input:
    tuple val(meta), path(image), path(bval), path(bvec), path(mask)

    output:
    tuple val(meta), path("*__image_n4.nii.gz")     , emit: image
    path "versions.yml"                             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def b0threshold = task.ext.b0threshold ? "-config BZeroThreshold $task.ext.b0threshold": ""
    def nb_voxels_between_knots = task.ext.nb_voxels_between_knots ?: "8"
    def shrink_factor = task.ext.shrink_factor ?: "4"
    def maxiter = task.ext.maxiter ?: "1000"
    def miniter = task.ext.miniter ?: "100"
    def retain = task.ext.retain ?: "0.6"
    def anat_mask = mask ? "-w $mask" : ""
    def dwi_mask = mask ? "-mask $mask" : ""
    def nthreads_mrtrix = task.ext.single_thread ? "-nthreads 0" : "-nthreads ${task.cpus}"

    """
    export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${task.ext.single_thread ? 1 : task.cpus}
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}
    export ANTS_RANDOM_SEED=${task.ext.ants_rng_seed ? task.ext.ants_rng_seed : "1234"}
    export MRTRIX_RNG_SEED=${task.ext.mrtrix_rng_seed ? task.ext.mrtrix_rng_seed : "1234"}

    # Checking if the input image is a DWI volume, if so, extract the b0 volume
    # as the reference volume to use in the parameters calculation. Final N4 will
    # be applied directly to the whole DWI volume. If anatomical, use the image
    # as the reference volume.
    if [[ -f "$bval" ]]
    then
        dwiextract $image -fslgrad $bvec $bval - -bzero $b0threshold ${nthreads_mrtrix} | mrmath - mean reference_for_formula.nii.gz -axis 3 ${nthreads_mrtrix}
    else
        cp $image reference_for_formula.nii.gz
    fi

    # Fetching the smallest dimension of the reference volume and the resolution.
    spacing=\$(mrinfo -spacing reference_for_formula.nii.gz | tr ' ' '\\n' | sort -n | head -n 1)
    smallest_dim=\$(mrinfo -size reference_for_formula.nii.gz | tr ' ' '\\n' | sort -n | head -n 1)

    # Computing the optimal number of stages to include in the pyramid.
    if (( \$(awk -v a="\$smallest_dim" -v b="$nb_voxels_between_knots" -v c="$shrink_factor" 'BEGIN {print (a <= b * c) ? 1 : 0}') )); then
        n_stages="1"
    else
        logval=\$(awk -v a="\$smallest_dim" -v b="$nb_voxels_between_knots" -v c="$shrink_factor" 'BEGIN {r = a / (b * c); print log(r) / log(2)}')
        n_stages=\$(echo "\$logval" | awk '{ if (\$1 == int(\$1)) print int(\$1)+1; else print int(\$1)+2 }')
    fi

    # Computing the BSpline parameters.
    bspline=\$(awk -v n="\$n_stages" -v b="$nb_voxels_between_knots" -v s="$shrink_factor" -v sp="\$spacing" 'BEGIN {print (2^(n - 1)) * b * s * sp}')

    # Setting the iterations.
    if [[ "\$n_stages" -eq 1 ]]; then
        iterations="$maxiter"
    else
        iterations=""
        slope=\$(awk -v min="$miniter" -v max="$maxiter" -v r="$retain" 'BEGIN {print (min - max) / (1 - r)}')
        intercept=\$(awk -v max="$maxiter" -v s="\$slope" -v r="$retain" 'BEGIN {print max - s * r}')
        n=\$(printf "%.0f" \$n_stages)
        step=\$(awk -v n="\$n" 'BEGIN {print 1 / (n - 1)}')

        for ((idx=0; idx<\$n; idx++)); do
            i=\$(awk -v idx="\$idx" -v step="\$step" 'BEGIN {print idx * step}')
            is_less=\$(awk -v i="\$i" -v r="$retain" 'BEGIN {print (i < r) ? 1 : 0}')


            if [[ "\$is_less" -eq 1 ]]; then
                iter=$maxiter
            else
                val=\$(awk -v i="\$i" -v s="\$slope" -v intercept="\$intercept" 'BEGIN {print i * s + intercept}')
                iter=\$(printf "%.0f" "\$val")
            fi

            if [[ -z "\$iterations" ]]; then
                iterations="\$iter"
            else
                iterations="\${iterations}x\$iter"
            fi
        done
    fi

    echo "Number of stages: \$n_stages"
    echo "Spacing: \$spacing"
    echo "Smallest dimension: \$smallest_dim"
    echo "Shrink factor: $shrink_factor"
    echo "Number of voxel between knots: $nb_voxels_between_knots"
    echo "Iterations: \$iterations"
    echo "BSpline: \$bspline"

    if [[ -f "$bval" ]]
    then
        dwibiascorrect ants \
            $image \
            ${prefix}__image_n4.nii.gz \
            -bias bias_field.nii.gz \
            -ants.b [\$bspline,3] \
            -ants.c [\$iterations,1e-6] \
            -ants.s $shrink_factor \
            -fslgrad $bvec $bval \
            $dwi_mask \
            ${nthreads_mrtrix}

    else
        N4BiasFieldCorrection -i $image\
            -o [${prefix}__image_n4.nii.gz, bias_field.nii.gz]\
            -c [\$iterations, 1e-6] -v 0\
            $anat_mask\
            -b [\$bspline, 3] \
            -s $shrink_factor
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(N4BiasFieldCorrection --version 2>&1 | sed -n 's/ANTs Version: v\\([0-9.]\\+\\)/\\1/p')
        mrtrix: \$(dwibiascorrect -version 2>&1 | sed -n 's/== dwibiascorrect \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    N4BiasFieldCorrection -h
    dwibiascorrect -h
    dwiextract -h

    touch ${prefix}__image_n4.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(N4BiasFieldCorrection --version 2>&1 | sed -n 's/ANTs Version: v\\([0-9.]\\+\\)/\\1/p')
        mrtrix: \$(dwibiascorrect -version 2>&1 | sed -n 's/== dwibiascorrect \\([0-9.]\\+\\).*/\\1/p')
    END_VERSIONS
    """
}
