process REGISTRATION_TRACTOGRAM {
    tag "$meta.id"
    label 'process_single'

    container "scilus/scilus:2.2.2"

    input:
    tuple val(meta), path(tractograms, arity: '1..*'), path(trk_reference), path(reference), path(transformations, arity: '1..2')

    output:
    tuple val(meta), path("*.{trk,tck,h5}") , emit: tractogram
    path "versions.yml"                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: "warped"
    trk_reference = "$trk_reference" ? "--reference $trk_reference" : ""
    def inverse = task.ext.inverse ? "--inverse" : ""
    def reverse_operation = task.ext.reverse_operation ? "--reverse_operation" : ""

    def invalid_management = task.ext.invalid_streamlines ?: "cut"
    def cut_invalid = invalid_management == "cut" ? "--cut_invalid" : ""
    def keep_invalid = invalid_management == "keep" ? "--keep_invalid" : ""
    def remove_invalid = invalid_management == "remove" ? "--remove_invalid" : ""
    def remove_single_point = task.ext.remove_single_point ? "--remove_single_point" : ""
    def remove_overlapping_points = task.ext.remove_overlapping_points ? "--remove_overlapping_points" : ""
    def threshold = task.ext.threshold ? "--threshold " + task.ext.threshold : ""
    def no_empty = task.ext.no_empty ? "--no_empty" : ""

    // Validate transformations when size is 2
    if (transformations.size() == 2) {
        def has_nii = transformations.any { it.toString().endsWith('.nii.gz') }
        def has_affine = transformations.any { it.toString().endsWith('.txt') || it.toString().endsWith('.mat') }
        if (!has_nii || !has_affine) {
            error "When providing 2 transformations, one must be .nii.gz and the other must be .txt or .mat"
        }
    }

    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    # Identify deformation and affine from transformations
    in_deformation=""
    affine=""

    for transform in ${transformations}; do
        if [[ "\$transform" == *.nii.gz ]]; then
            in_deformation="--in_deformation \$transform"
        elif [[ "\$transform" == *.mat ]] || [[ "\$transform" == *.txt ]]; then
            affine="\$transform"
        fi
    done

    # Convert .txt affine to .mat if necessary
    if [[ "\$affine" == *.txt ]]; then
        ConvertTransformFile 3 \$affine affine.mat --convertToAffineType \
            && affine="affine.mat" \
            || echo "TXT affine transform file conversion failed, using original file."
    fi

    for tractogram in ${tractograms}; do
        ext=\${tractogram#*.}
        bname=\$(basename \${tractogram} .\${ext} | sed 's/${prefix}_\\+//')
        name=${prefix}_\${bname}_${suffix}.\${ext}

        if [[ \$ext == "h5" ]]; then

            scil_tractogram_apply_transform_to_hdf5 \$tractogram \
                $reference \
                \$affine \
                \$name \
                \$in_deformation \
                $inverse \
                $reverse_operation \
                $trk_reference \
                $remove_invalid \
                $keep_invalid \
                $cut_invalid -f

        else

            scil_tractogram_apply_transform \$tractogram $reference \$affine \$name \
                \$in_deformation \
                $inverse \
                $reverse_operation \
                $trk_reference \
                --keep_invalid -f

            if [[ "$invalid_management" == "keep" ]]; then
                echo "Skip invalid streamline detection: \$name"
                continue
            fi

            scil_tractogram_remove_invalid \$name \$name \
                $cut_invalid\
                $remove_single_point\
                $remove_overlapping_points\
                $threshold\
                $no_empty\
                -f
        fi
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def suffix = task.ext.suffix ?: "warped"
    """
    scil_tractogram_apply_transform -h
    scil_tractogram_remove_invalid -h

    for tractogram in ${tractograms}; do
        ext=\${tractogram#*.}
        bname=\$(basename \${tractogram} .\${ext} | sed 's/${prefix}_\\+//')
        name=${prefix}_\${bname}_${suffix}.\${ext}
        touch \$name
    done

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        ants: \$(antsRegistration --version | grep "Version" | sed -E 's/.*: v?([0-9.a-zA-Z-]+).*/\\1/')
        scilpy: \$(uv pip -q -n list | grep scilpy | tr -s ' ' | cut -d' ' -f2)
    END_VERSIONS
    """
}
