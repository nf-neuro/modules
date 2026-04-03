process REGISTRATION_SYNTHMORPH {
    tag "$meta.id"
    label 'process_high'

    container "freesurfer/synthmorph:4"
    containerOptions((workflow.containerEngine == 'docker') ? '--entrypoint ""' : "")

    input:
    tuple val(meta), path(fixed_image), path(moving_image)

    output:
    tuple val(meta), path("*_warped.nii.gz")                               , emit: image_warped
    tuple val(meta), path("*_forward{0,1,_standalone}_affine.lta")         , emit: forward_affine, optional: true
    tuple val(meta), path("*_forward0_deform.nii.gz")                      , emit: forward_warp, optional: true
    tuple val(meta), path("*_backward1_deform.nii.gz")                     , emit: backward_warp, optional: true
    tuple val(meta), path("*_backward{0,_standalone}_affine.lta")          , emit: backward_affine, optional: true
    tuple val(meta), path("*_forward[!_]*.{lta,nii.gz}", arity: '1..*')    , emit: forward_image_transform
    tuple val(meta), path("*_backward[!_]*.{lta,nii.gz}", arity: '1..*')   , emit: backward_image_transform
    tuple val(meta), path("*_backward[!_]*.{lta,nii.gz}", arity: '1..*')   , emit: forward_tractogram_transform
    tuple val(meta), path("*_forward[!_]*.{lta,nii.gz}", arity: '1..*')    , emit: backward_tractogram_transform
    path "versions.yml"                                                    , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"

    def models = task.ext.models ?: ["affine", "deform"]
    def weights = (task.ext.weights ?: [null] * models.size()).collect{ it ? "-w $it" : "none" }.join(" ")
    def use_gpu = task.ext.use_gpu ? "-g" : ""
    def regularization = "-r ${task.ext.regularization ?: 0.5}"
    def steps = "-n ${task.ext.steps ?: 7 }"
    def extent = "-e ${task.ext.extent ?: 256}"
    def update_header = task.ext.disable_resampling ? "-H" : ""
    def nthreads = task.ext.single_thread ? 1 : task.cpus

    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}
    export CUDA_VISIBLE_DEVICES="-1"

    echo "Available memory : ${task.memory}"

    moving=$moving_image
    mv $fixed_image fixed.nii.gz

    declare -A extension=(  ["affine"]="lta" \
                            ["rigid"]="lta" \
                            ["deform"]="nii.gz" \
                            ["joint"]="nii.gz" )

    weights=( $weights )

    i=0
    skip=0
    j=${models.size()}
    initializer=""
    init_assoc=""
    for model in ${models.join(" ")}; do
        echo "Processing model: \$model"
        # Post-incrementation ensure no error on last index = 0
        ((j--))

        weight=""
        if [ "\${weights[i + skip]}" != "none" ]; then
            weight="-w \${weights[i + skip]}"

            if [ "\$model" = "joint" ]; then
                # Pre-incrementation ensure no error on first index = 0
                ((++skip))
                if [ "\${weights[i + skip]}" = "none" ]; then
                    echo "Joint deformations need 2 weights, only 1 given"
                    exit 1
                else
                    weight="\$weight -w \${weights[i + skip]}"
                fi
            fi
        fi

        args=""
        if [ \$model = "joint" ] || [ \$model = "deform" ]; then
            args="$regularization $steps"
        else
            args="$update_header"
        fi

        if [ \$initializer ]; then
            args="\$args -i \$initializer"
        fi

        mri_synthmorph register \$moving fixed.nii.gz -v -m \$model \$weight \$args \
            -t ${prefix}_forward\${j}_\$model.\${extension[\$model]} \
            -T ${prefix}_backward\${i}_\$model.\${extension[\$model]} \
            -o warped.nii.gz -j ${nthreads} $extent $use_gpu

        if [ \$initializer ]; then
            # Retag initializer file to standalone using sed
            #  - replace the number after forward/backward to standalone
            mv \$initializer \$(echo "\$initializer" | sed -r 's/(_forward|_backward)[[:digit:]]+/\\1_standalone/')
            mv \$init_assoc \$(echo "\$init_assoc" | sed -r 's/(_forward|_backward)[[:digit:]]+/\\1_standalone/')
        fi

        if [ \${extension[\$model]} = "lta" ]; then
            initializer=${prefix}_forward\${j}_\$model.\${extension[\$model]}
            init_assoc=${prefix}_backward\${i}_\$model.\${extension[\$model]}
        else
            moving=warped.nii.gz
        fi

        # Pre-incrementation ensure no error on first index = 0
        ((++i))

    done

    mv warped.nii.gz ${prefix}_warped.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        synthmorph: 4
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    mri_synthmorph -h

    touch ${prefix}_warped.nii.gz
    touch ${prefix}_forward1_affine.lta
    touch ${prefix}_forward0_warp.nii.gz
    touch ${prefix}_backward1_warp.nii.gz
    touch ${prefix}_backward0_affine.lta

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        synthmorph: 4
    END_VERSIONS
    """
}
